# CrowdFund Platform

A decentralized crowdfunding platform built on Stacks blockchain that enables creators to launch campaigns and backers to support innovative projects while earning rewards.

## Features

- **Campaign Creation**: Founders can create funding campaigns with customizable reward tiers
- **Backer Registration**: Users register with interest categories to discover relevant projects
- **Smart Matching**: Automatic matching between backer interests and campaign categories
- **Reward System**: Backers earn rewards for supporting campaigns
- **Platform Governance**: Admin controls for categories and fee management

## Smart Contract Functions

### Admin Functions
- `set-platform-admin`: Update platform administrator
- `set-platform-fee`: Configure platform fee percentage
- `add-category`: Add new project categories

### User Functions
- `register-backer`: Register as a project backer
- `update-interests`: Modify interest categories
- `pause-backing`/`resume-backing`: Control backing activity

### Campaign Functions
- `create-campaign`: Launch a new funding campaign
- `back-campaign`: Support a campaign and earn rewards
- `claim-contributions`: Withdraw earned rewards

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Register as a backer with your interests
3. Browse campaigns matching your interests
4. Back projects to earn rewards
5. Claim your contributions when ready

## License

MIT License
\`\`\`

```clarity file="project-2-skillmarket/contracts/skill-marketplace.clar"
;; SkillMarket - A decentralized freelancer skill verification and payment platform
;; Clients hire verified freelancers and pay for completed work through smart contracts

;; Data storage
(define-map freelancer-profiles principal {
  active: bool,
  specialties: (list 10 uint),
  earnings: uint,
  last-payout: uint,
  project-count: uint
})

(define-map work-contracts uint {
  client: principal,
  budget: uint,
  hourly-rate: uint,
  open: bool,
  skill-category: uint,
  applicant-count: uint,
  posted-at: uint
})

(define-map work-applications {freelancer: principal, contract-id: uint} {
  timestamp: uint,
  completed: bool
})

(define-map skill-categories uint (string-ascii 64))

;; Constants
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_DATA (err u301))
(define-constant ERR_FREELANCER_NOT_FOUND (err u302))
(define-constant ERR_CONTRACT_NOT_FOUND (err u303))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u304))
(define-constant ERR_ALREADY_REGISTERED (err u305))
(define-constant ERR_ALREADY_APPLIED (err u306))
(define-constant ERR_INVALID_WALLET (err u307))
(define-constant ERR_INVALID_RATE (err u308))
(define-constant ERR_SKILL_NOT_FOUND (err u309))

(define-constant EMPTY_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_HOURLY_RATE u1)
(define-constant MAX_HOURLY_RATE u1000)
(define-constant MIN_PROJECT_BUDGET u1000)
(define-constant MAX_SKILL_ID u1000)

;; Data variables
(define-data-var marketplace-owner principal tx-sender)
(define-data-var next-contract-id uint u1)
(define-data-var service-fee-percent uint u5) ;; 5% fee
(define-data-var service-revenue uint u0)

;; Admin functions
(define-public (set-marketplace-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get marketplace-owner)) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq new-owner EMPTY_ADDRESS)) ERR_INVALID_WALLET)
    (ok (var-set marketplace-owner new-owner))))

(define-public (set-service-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get marketplace-owner)) ERR_UNAUTHORIZED)
    (asserts! (&lt;= new-fee u20) ERR_INVALID_DATA) ;; Max 20% fee
    (ok (var-set service-fee-percent new-fee))))

(define-public (add-skill-category (skill-id uint) (skill-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get marketplace-owner)) ERR_UNAUTHORIZED)
    (asserts! (> (len skill-name) u0) ERR_INVALID_DATA)
    (asserts! (&lt; skill-id MAX_SKILL_ID) ERR_INVALID_DATA)
    (asserts! (is-none (map-get? skill-categories skill-id)) ERR_ALREADY_REGISTERED)
    (ok (map-set skill-categories skill-id skill-name))))

;; User functions
(define-public (register-freelancer (specialties (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? freelancer-profiles tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (validate-specialties specialties) ERR_INVALID_DATA)
    (ok (map-set freelancer-profiles tx-sender {
      active: true,
      specialties: specialties,
      earnings: u0,
      last-payout: u0,
      project-count: u0
    }))))

(define-public (update-specialties (specialties (list 10 uint)))
  (let ((freelancer-profile (unwrap! (map-get? freelancer-profiles tx-sender) ERR_FREELANCER_NOT_FOUND)))
    (asserts! (validate-specialties specialties) ERR_INVALID_DATA)
    (ok (map-set freelancer-profiles tx-sender (merge freelancer-profile {specialties: specialties})))))

(define-public (pause-freelancing)
  (let ((freelancer-profile (unwrap! (map-get? freelancer-profiles tx-sender) ERR_FREELANCER_NOT_FOUND)))
    (ok (map-set freelancer-profiles tx-sender (merge freelancer-profile {active: false})))))

(define-public (resume-freelancing)
  (let ((freelancer-profile (unwrap! (map-get? freelancer-profiles tx-sender) ERR_FREELANCER_NOT_FOUND)))
    (ok (map-set freelancer-profiles tx-sender (merge freelancer-profile {active: true})))))

;; Client functions
(define-public (post-work-contract (budget uint) (hourly-rate uint) (skill-category uint) (stx-amount uint))
  (begin
    (asserts! (>= budget MIN_PROJECT_BUDGET) ERR_INVALID_DATA)
    (asserts! (and (>= hourly-rate MIN_HOURLY_RATE) (&lt;= hourly-rate MAX_HOURLY_RATE)) ERR_INVALID_DATA)
    (asserts! (is-some (map-get? skill-categories skill-category)) ERR_SKILL_NOT_FOUND)
    (asserts! (>= stx-amount budget) ERR_INSUFFICIENT_PAYMENT)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((contract-id (var-get next-contract-id)))
      ;; Create work contract
      (map-set work-contracts contract-id {
        client: tx-sender,
        budget: budget,
        hourly-rate: hourly-rate,
        open: true,
        skill-category: skill-category,
        applicant-count: u0,
        posted-at: u0
      })
      
      ;; Increment contract ID
      (var-set next-contract-id (+ contract-id u1))
      (ok contract-id))))

(define-public (close-contract (contract-id uint))
  (let ((contract (unwrap! (map-get? work-contracts contract-id) ERR_CONTRACT_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get client contract)) ERR_UNAUTHORIZED)
    (ok (map-set work-contracts contract-id (merge contract {open: false})))))

(define-public (reopen-contract (contract-id uint))
  (let ((contract (unwrap! (map-get? work-contracts contract-id) ERR_CONTRACT_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get client contract)) ERR_UNAUTHORIZED)
    (ok (map-set work-contracts contract-id (merge contract {open: true})))))

(define-public (increase-budget (contract-id uint) (additional-budget uint))
  (let ((contract (unwrap! (map-get? work-contracts contract-id) ERR_CONTRACT_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get client contract)) ERR_UNAUTHORIZED)
    (asserts! (> additional-budget u0) ERR_INVALID_DATA)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? additional-budget tx-sender (as-contract tx-sender)))
    
    (ok (map-set work-contracts contract-id 
      (merge contract {budget: (+ (get budget contract) additional-budget)})))))

;; Helper function to check if a skill matches freelancer specialties
(define-private (check-specialty-match (skill-category uint) (specialties (list 10 uint)))
  (or
    (and (> (len specialties) u0) (is-eq skill-category (unwrap-panic (element-at specialties u0))))
    (and (> (len specialties) u1) (is-eq skill-category (unwrap-panic (element-at specialties u1))))
    (and (> (len specialties) u2) (is-eq skill-category (unwrap-panic (element-at specialties u2))))
    (and (> (len specialties) u3) (is-eq skill-category (unwrap-panic (element-at specialties u3))))
    (and (> (len specialties) u4) (is-eq skill-category (unwrap-panic (element-at specialties u4))))
    (and (> (len specialties) u5) (is-eq skill-category (unwrap-panic (element-at specialties u5))))
    (and (> (len specialties) u6) (is-eq skill-category (unwrap-panic (element-at specialties u6))))
    (and (> (len specialties) u7) (is-eq skill-category (unwrap-panic (element-at specialties u7))))
    (and (> (len specialties) u8) (is-eq skill-category (unwrap-panic (element-at specialties u8))))
    (and (> (len specialties) u9) (is-eq skill-category (unwrap-panic (element-at specialties u9))))
  ))

;; Work application and payment
(define-public (apply-for-work (contract-id uint))
  (let (
    (freelancer-profile (unwrap! (map-get? freelancer-profiles tx-sender) ERR_FREELANCER_NOT_FOUND))
    (contract (unwrap! (map-get? work-contracts contract-id) ERR_CONTRACT_NOT_FOUND))
    (application-key {freelancer: tx-sender, contract-id: contract-id})
  )
    ;; Validate conditions
    (asserts! (get active freelancer-profile) ERR_FREELANCER_NOT_FOUND)
    (asserts! (get open contract) ERR_CONTRACT_NOT_FOUND)
    (asserts! (is-none (map-get? work-applications application-key)) ERR_ALREADY_APPLIED)
    (asserts! (>= (get budget contract) (get hourly-rate contract)) ERR_INSUFFICIENT_PAYMENT)
    (asserts! (check-specialty-match (get skill-category contract) (get specialties freelancer-profile)) ERR_INVALID_DATA)
    
    ;; Calculate payment
    (let (
      (hourly-rate (get hourly-rate contract))
      (service-fee (/ (* hourly-rate (var-get service-fee-percent)) u100))
      (freelancer-payment (- hourly-rate service-fee))
    )
      ;; Record the application
      (map-set work-applications application-key {timestamp: u0, completed: true})
      
      ;; Update contract stats
      (map-set work-contracts contract-id (merge contract {
        budget: (- (get budget contract) hourly-rate),
        applicant-count: (+ (get applicant-count contract) u1)
      }))
      
      ;; Update freelancer stats
      (map-set freelancer-profiles tx-sender (merge freelancer-profile {
        earnings: (+ (get earnings freelancer-profile) freelancer-payment),
        project-count: (+ (get project-count freelancer-profile) u1)
      }))
      
      ;; Update service revenue
      (var-set service-revenue (+ (var-get service-revenue) service-fee))
      
      (ok freelancer-payment))))

(define-public (withdraw-earnings)
  (let ((freelancer-profile (unwrap! (map-get? freelancer-profiles tx-sender) ERR_FREELANCER_NOT_FOUND)))
    (let ((earnings (get earnings freelancer-profile)))
      (asserts! (> earnings u0) ERR_INSUFFICIENT_PAYMENT)
      
      ;; Transfer STX to freelancer
      (try! (as-contract (stx-transfer? earnings tx-sender tx-sender)))
      
      ;; Update freelancer profile
      (map-set freelancer-profiles tx-sender (merge freelancer-profile {
        earnings: u0,
        last-payout: u0
      }))
      
      (ok earnings))))

(define-public (withdraw-service-revenue)
  (begin
    (asserts! (is-eq tx-sender (var-get marketplace-owner)) ERR_UNAUTHORIZED)
    (let ((amount (var-get service-revenue)))
      (asserts! (> amount u0) ERR_INSUFFICIENT_PAYMENT)
      
      ;; Transfer STX to marketplace owner
      (try! (as-contract (stx-transfer? amount tx-sender (var-get marketplace-owner))))
      
      ;; Reset service revenue
      (var-set service-revenue u0)
      
      (ok amount))))

;; Helper function to check if a skill is valid
(define-private (is-valid-skill (skill uint))
  (is-some (map-get? skill-categories skill)))

;; Helper function to count valid skills in a list
(define-private (count-valid-skills (specialties (list 10 uint)))
  (+ 
    (if (and (> (len specialties) u0) (is-valid-skill (unwrap-panic (element-at specialties u0)))) u1 u0)
    (if (and (> (len specialties) u1) (is-valid-skill (unwrap-panic (element-at specialties u1)))) u1 u0)
    (if (and (> (len specialties) u2) (is-valid-skill (unwrap-panic (element-at specialties u2)))) u1 u0)
    (if (and (> (len specialties) u3) (is-valid-skill (unwrap-panic (element-at specialties u3)))) u1 u0)
    (if (and (> (len specialties) u4) (is-valid-skill (unwrap-panic (element-at specialties u4)))) u1 u0)
    (if (and (> (len specialties) u5) (is-valid-skill (unwrap-panic (element-at specialties u5)))) u1 u0)
    (if (and (> (len specialties) u6) (is-valid-skill (unwrap-panic (element-at specialties u6)))) u1 u0)
    (if (and (> (len specialties) u7) (is-valid-skill (unwrap-panic (element-at specialties u7)))) u1 u0)
    (if (and (> (len specialties) u8) (is-valid-skill (unwrap-panic (element-at specialties u8)))) u1 u0)
    (if (and (> (len specialties) u9) (is-valid-skill (unwrap-panic (element-at specialties u9)))) u1 u0)
  ))

;; Validate freelancer specialties
(define-private (validate-specialties (specialties (list 10 uint)))
  (let ((specialties-len (len specialties)))
    (and 
      (> specialties-len u0)
      (&lt;= specialties-len u10)
      (is-eq specialties-len (count-valid-skills specialties)))))

;; Read-only functions
(define-read-only (get-freelancer-profile (freelancer principal))
  (map-get? freelancer-profiles freelancer))

(define-read-only (get-work-contract (contract-id uint))
  (map-get? work-contracts contract-id))

(define-read-only (get-skill-category (skill-id uint))
  (map-get? skill-categories skill-id))

(define-read-only (get-service-fee)
  (var-get service-fee-percent))

(define-read-only (get-service-revenue)
  (var-get service-revenue))

(define-read-only (get-work-application (freelancer principal) (contract-id uint))
  (map-get? work-applications {freelancer: freelancer, contract-id: contract-id}))
