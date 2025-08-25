;; CrowdFund - A decentralized crowdfunding platform for innovative projects
;; Backers fund campaigns to support creators and earn exclusive rewards

;; Data storage
(define-map backer-accounts principal {
  verified: bool,
  interests: (list 10 uint),
  contributions: uint,
  last-reward: uint,
  backed-count: uint
})

(define-map funding-campaigns uint {
  founder: principal,
  target-amount: uint,
  reward-tier: uint,
  live: bool,
  category-id: uint,
  supporter-count: uint,
  launched-at: uint
})

(define-map contribution-history {backer: principal, campaign-id: uint} {
  timestamp: uint,
  rewarded: bool
})

(define-map project-categories uint (string-ascii 64))

;; Constants
(define-constant ERR_ACCESS_DENIED (err u200))
(define-constant ERR_INVALID_INPUT (err u201))
(define-constant ERR_BACKER_MISSING (err u202))
(define-constant ERR_CAMPAIGN_MISSING (err u203))
(define-constant ERR_INSUFFICIENT_BALANCE (err u204))
(define-constant ERR_ALREADY_EXISTS (err u205))
(define-constant ERR_ALREADY_BACKED (err u206))
(define-constant ERR_INVALID_ADDRESS (err u207))
(define-constant ERR_INVALID_AMOUNT (err u208))
(define-constant ERR_CATEGORY_MISSING (err u209))

(define-constant NULL_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_REWARD_TIER u1)
(define-constant MAX_REWARD_TIER u1000)
(define-constant MIN_CAMPAIGN_TARGET u1000)
(define-constant MAX_CATEGORY_ID u1000)

;; Data variables
(define-data-var platform-admin principal tx-sender)
(define-data-var next-campaign-id uint u1)
(define-data-var platform-fee-rate uint u5) ;; 5% fee
(define-data-var platform-treasury uint u0)

;; Admin functions
(define-public (set-platform-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_ACCESS_DENIED)
    (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (ok (var-set platform-admin new-admin))))

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_ACCESS_DENIED)
    (asserts! (<= new-fee u20) ERR_INVALID_INPUT) ;; Max 20% fee
    (ok (var-set platform-fee-rate new-fee))))

(define-public (add-category (category-id uint) (category-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_ACCESS_DENIED)
    (asserts! (> (len category-name) u0) ERR_INVALID_INPUT)
    (asserts! (< category-id MAX_CATEGORY_ID) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? project-categories category-id)) ERR_ALREADY_EXISTS)
    (ok (map-set project-categories category-id category-name))))

;; User functions
(define-public (register-backer (interests (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? backer-accounts tx-sender)) ERR_ALREADY_EXISTS)
    (asserts! (validate-interests interests) ERR_INVALID_INPUT)
    (ok (map-set backer-accounts tx-sender {
      verified: true,
      interests: interests,
      contributions: u0,
      last-reward: u0,
      backed-count: u0
    }))))

(define-public (update-interests (interests (list 10 uint)))
  (let ((backer-account (unwrap! (map-get? backer-accounts tx-sender) ERR_BACKER_MISSING)))
    (asserts! (validate-interests interests) ERR_INVALID_INPUT)
    (ok (map-set backer-accounts tx-sender (merge backer-account {interests: interests})))))

(define-public (pause-backing)
  (let ((backer-account (unwrap! (map-get? backer-accounts tx-sender) ERR_BACKER_MISSING)))
    (ok (map-set backer-accounts tx-sender (merge backer-account {verified: false})))))

(define-public (resume-backing)
  (let ((backer-account (unwrap! (map-get? backer-accounts tx-sender) ERR_BACKER_MISSING)))
    (ok (map-set backer-accounts tx-sender (merge backer-account {verified: true})))))

;; Campaign creator functions
(define-public (create-campaign (target-amount uint) (reward-tier uint) (category-id uint) (stx-amount uint))
  (begin
    (asserts! (>= target-amount MIN_CAMPAIGN_TARGET) ERR_INVALID_INPUT)
    (asserts! (and (>= reward-tier MIN_REWARD_TIER) (<= reward-tier MAX_REWARD_TIER)) ERR_INVALID_INPUT)
    (asserts! (is-some (map-get? project-categories category-id)) ERR_CATEGORY_MISSING)
    (asserts! (>= stx-amount target-amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((campaign-id (var-get next-campaign-id)))
      ;; Create campaign
      (map-set funding-campaigns campaign-id {
        founder: tx-sender,
        target-amount: target-amount,
        reward-tier: reward-tier,
        live: true,
        category-id: category-id,
        supporter-count: u0,
        launched-at: u0
      })
      
      ;; Increment campaign ID
      (var-set next-campaign-id (+ campaign-id u1))
      (ok campaign-id))))

(define-public (pause-campaign (campaign-id uint))
  (let ((campaign (unwrap! (map-get? funding-campaigns campaign-id) ERR_CAMPAIGN_MISSING)))
    (asserts! (is-eq tx-sender (get founder campaign)) ERR_ACCESS_DENIED)
    (ok (map-set funding-campaigns campaign-id (merge campaign {live: false})))))

(define-public (resume-campaign (campaign-id uint))
  (let ((campaign (unwrap! (map-get? funding-campaigns campaign-id) ERR_CAMPAIGN_MISSING)))
    (asserts! (is-eq tx-sender (get founder campaign)) ERR_ACCESS_DENIED)
    (ok (map-set funding-campaigns campaign-id (merge campaign {live: true})))))

(define-public (add-campaign-funds (campaign-id uint) (additional-funds uint))
  (let ((campaign (unwrap! (map-get? funding-campaigns campaign-id) ERR_CAMPAIGN_MISSING)))
    (asserts! (is-eq tx-sender (get founder campaign)) ERR_ACCESS_DENIED)
    (asserts! (> additional-funds u0) ERR_INVALID_INPUT)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? additional-funds tx-sender (as-contract tx-sender)))
    
    (ok (map-set funding-campaigns campaign-id 
      (merge campaign {target-amount: (+ (get target-amount campaign) additional-funds)})))))

;; Helper function to check if a category matches user interests
(define-private (check-interest-match (category-id uint) (interests (list 10 uint)))
  (or
    (and (> (len interests) u0) (is-eq category-id (unwrap-panic (element-at interests u0))))
    (and (> (len interests) u1) (is-eq category-id (unwrap-panic (element-at interests u1))))
    (and (> (len interests) u2) (is-eq category-id (unwrap-panic (element-at interests u2))))
    (and (> (len interests) u3) (is-eq category-id (unwrap-panic (element-at interests u3))))
    (and (> (len interests) u4) (is-eq category-id (unwrap-panic (element-at interests u4))))
    (and (> (len interests) u5) (is-eq category-id (unwrap-panic (element-at interests u5))))
    (and (> (len interests) u6) (is-eq category-id (unwrap-panic (element-at interests u6))))
    (and (> (len interests) u7) (is-eq category-id (unwrap-panic (element-at interests u7))))
    (and (> (len interests) u8) (is-eq category-id (unwrap-panic (element-at interests u8))))
    (and (> (len interests) u9) (is-eq category-id (unwrap-panic (element-at interests u9))))
  ))

;; Backing and rewards
(define-public (back-campaign (campaign-id uint))
  (let (
    (backer-account (unwrap! (map-get? backer-accounts tx-sender) ERR_BACKER_MISSING))
    (campaign (unwrap! (map-get? funding-campaigns campaign-id) ERR_CAMPAIGN_MISSING))
    (contribution-key {backer: tx-sender, campaign-id: campaign-id})
  )
    ;; Validate conditions
    (asserts! (get verified backer-account) ERR_BACKER_MISSING)
    (asserts! (get live campaign) ERR_CAMPAIGN_MISSING)
    (asserts! (is-none (map-get? contribution-history contribution-key)) ERR_ALREADY_BACKED)
    (asserts! (>= (get target-amount campaign) (get reward-tier campaign)) ERR_INSUFFICIENT_BALANCE)
    (asserts! (check-interest-match (get category-id campaign) (get interests backer-account)) ERR_INVALID_INPUT)
    
    ;; Calculate rewards
    (let (
      (reward-tier (get reward-tier campaign))
      (platform-fee (/ (* reward-tier (var-get platform-fee-rate)) u100))
      (backer-reward (- reward-tier platform-fee))
    )
      ;; Record the contribution
      (map-set contribution-history contribution-key {timestamp: u0, rewarded: true})
      
      ;; Update campaign stats
      (map-set funding-campaigns campaign-id (merge campaign {
        target-amount: (- (get target-amount campaign) reward-tier),
        supporter-count: (+ (get supporter-count campaign) u1)
      }))
      
      ;; Update backer stats
      (map-set backer-accounts tx-sender (merge backer-account {
        contributions: (+ (get contributions backer-account) backer-reward),
        backed-count: (+ (get backed-count backer-account) u1)
      }))
      
      ;; Update platform treasury
      (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
      
      (ok backer-reward))))

(define-public (claim-contributions)
  (let ((backer-account (unwrap! (map-get? backer-accounts tx-sender) ERR_BACKER_MISSING)))
    (let ((contributions (get contributions backer-account)))
      (asserts! (> contributions u0) ERR_INSUFFICIENT_BALANCE)
      
      ;; Transfer STX to backer
      (try! (as-contract (stx-transfer? contributions tx-sender tx-sender)))
      
      ;; Update backer account
      (map-set backer-accounts tx-sender (merge backer-account {
        contributions: u0,
        last-reward: u0
      }))
      
      (ok contributions))))

(define-public (withdraw-platform-treasury)
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_ACCESS_DENIED)
    (let ((amount (var-get platform-treasury)))
      (asserts! (> amount u0) ERR_INSUFFICIENT_BALANCE)
      
      ;; Transfer STX to platform admin
      (try! (as-contract (stx-transfer? amount tx-sender (var-get platform-admin))))
      
      ;; Reset platform treasury
      (var-set platform-treasury u0)
      
      (ok amount))))

;; Helper function to check if a category is valid
(define-private (is-valid-category (category uint))
  (is-some (map-get? project-categories category)))

;; Helper function to count valid categories in a list
(define-private (count-valid-categories (interests (list 10 uint)))
  (+ 
    (if (and (> (len interests) u0) (is-valid-category (unwrap-panic (element-at interests u0)))) u1 u0)
    (if (and (> (len interests) u1) (is-valid-category (unwrap-panic (element-at interests u1)))) u1 u0)
    (if (and (> (len interests) u2) (is-valid-category (unwrap-panic (element-at interests u2)))) u1 u0)
    (if (and (> (len interests) u3) (is-valid-category (unwrap-panic (element-at interests u3)))) u1 u0)
    (if (and (> (len interests) u4) (is-valid-category (unwrap-panic (element-at interests u4)))) u1 u0)
    (if (and (> (len interests) u5) (is-valid-category (unwrap-panic (element-at interests u5)))) u1 u0)
    (if (and (> (len interests) u6) (is-valid-category (unwrap-panic (element-at interests u6)))) u1 u0)
    (if (and (> (len interests) u7) (is-valid-category (unwrap-panic (element-at interests u7)))) u1 u0)
    (if (and (> (len interests) u8) (is-valid-category (unwrap-panic (element-at interests u8)))) u1 u0)
    (if (and (> (len interests) u9) (is-valid-category (unwrap-panic (element-at interests u9)))) u1 u0)
  ))

;; Validate backer interests
(define-private (validate-interests (interests (list 10 uint)))
  (let ((interests-len (len interests)))
    (and 
      (> interests-len u0)
      (<= interests-len u10)
      (is-eq interests-len (count-valid-categories interests)))))

;; Read-only functions
(define-read-only (get-backer-account (backer principal))
  (map-get? backer-accounts backer))

(define-read-only (get-campaign (campaign-id uint))
  (map-get? funding-campaigns campaign-id))

(define-read-only (get-category (category-id uint))
  (map-get? project-categories category-id))

(define-read-only (get-platform-fee)
  (var-get platform-fee-rate))

(define-read-only (get-platform-treasury)
  (var-get platform-treasury))

(define-read-only (get-contribution-record (backer principal) (campaign-id uint))
  (map-get? contribution-history {backer: backer, campaign-id: campaign-id}))
