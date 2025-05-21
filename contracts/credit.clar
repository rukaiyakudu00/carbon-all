;; CARBON-ALL: Decentralized Carbon Credit System

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NO_PERMISSION (err u100))
(define-constant ERR_ALREADY_REGISTERED (err u101))
(define-constant ERR_NOT_REGISTERED (err u102))
(define-constant ERR_SELF_TRANSFER (err u103))
(define-constant ERR_INVALID_PARAMETERS (err u104))
(define-constant ERR_INVALID_DATA (err u105))
(define-constant ERR_INSUFFICIENT_CREDITS (err u106))
(define-constant ERR_ALREADY_VERIFIED (err u107))

;; Data Structures

;; Carbon project information
(define-map carbon-projects
  { project-id: (string-ascii 64) }
  {
    name: (string-ascii 256),
    developer: principal,
    timestamp: uint,
    category: (string-ascii 64),
    description: (string-utf8 1024),
    location: (string-ascii 128),
    verified: bool
  }
)

;; Verification data
(define-map verification-records
  {
    project-id: (string-ascii 64),
    period-end: uint
  }
  {
    timestamp: uint,
    reduction-tons: uint,
    methodology: (string-ascii 128),
    verifier: principal
  }
)

;; Credit balances per entity
(define-map credit-balances
  { 
    owner: principal,
    vintage: uint
  }
  { amount: uint }
)

;; Project developer stats
(define-map developer-stats
  { developer: principal }
  {
    total-projects: uint,
    total-credits-issued: uint,
    reputation-score: uint
  }
)

;; Category metrics
(define-map category-metrics
  { category: (string-ascii 64) }
  {
    total-projects: uint,
    total-credits: uint
  }
)

;; Retired credits tracking
(define-map retired-credits
  { 
    owner: principal,
    vintage: uint
  }
  { amount: uint }
)

;; Approved verifiers
(define-map approved-verifiers
  { verifier: principal }
  { 
    active: bool,
    categories: (list 10 (string-ascii 64))
  }
)

;; Validation functions

;; Validate string-ascii is not empty
(define-private (validate-string-ascii (input (string-ascii 256)))
  (> (len input) u0)
)

;; Validate string-utf8 is not empty
(define-private (validate-string-utf8 (input (string-utf8 1024)))
  (> (len input) u0)
)

;; Validate project-id
(define-private (validate-project-id (project-id (string-ascii 64)))
  (and
    (> (len project-id) u0)
    (<= (len project-id) u64)
  )
)

;; Validate principal is not null
(define-private (validate-principal (user principal))
  (not (is-eq user 'SPNWZ5V2TPWGQGVDR6T7B6RQ4XMGZ4PXTEE0VQ0S))  ;; Check against zero/null address
)

;; Initialize functions

;; Initialize developer stats
(define-private (initialize-developer-stats (developer principal))
  (let ((developer-data (map-get? developer-stats { developer: developer })))
    (if (is-some developer-data)
      true
      (map-set developer-stats
        { developer: developer }
        {
          total-projects: u0,
          total-credits-issued: u0,
          reputation-score: u100
        }
      )
    )
  )
)

;; Initialize category metrics
(define-private (initialize-category-metrics (category (string-ascii 64)))
  (let ((category-data (map-get? category-metrics { category: category })))
    (if (is-some category-data)
      true
      (map-set category-metrics
        { category: category }
        {
          total-projects: u0,
          total-credits: u0
        }
      )
    )
  )
)

;; Initialize credit balances
(define-private (initialize-credit-balance (owner principal) (vintage uint))
  (let ((balance-data (map-get? credit-balances { owner: owner, vintage: vintage })))
    (if (is-some balance-data)
      true
      (map-set credit-balances
        { owner: owner, vintage: vintage }
        { amount: u0 }
      )
    )
  )
)

;; Initialize retired credits
(define-private (initialize-retired-credits (owner principal) (vintage uint))
  (let ((retired-data (map-get? retired-credits { owner: owner, vintage: vintage })))
    (if (is-some retired-data)
      true
      (map-set retired-credits
        { owner: owner, vintage: vintage }
        { amount: u0 }
      )
    )
  )
)

;; Register a new carbon project
(define-public (register-project
                (project-id (string-ascii 64))
                (name (string-ascii 256))
                (category (string-ascii 64))
                (description (string-utf8 1024))
                (location (string-ascii 128)))
  (let
    ((developer tx-sender)
     (existing-project (map-get? carbon-projects { project-id: project-id })))
    (begin
      ;; Validate inputs
      (asserts! (validate-project-id project-id) ERR_INVALID_DATA)
      (asserts! (validate-string-ascii name) ERR_INVALID_DATA)
      (asserts! (validate-string-ascii category) ERR_INVALID_DATA)
      (asserts! (validate-string-utf8 description) ERR_INVALID_DATA)
      (asserts! (validate-string-ascii location) ERR_INVALID_DATA)
      
      (asserts! (is-none existing-project) ERR_ALREADY_REGISTERED)
      
      ;; Initialize or update developer stats
      (initialize-developer-stats developer)
      (map-set developer-stats
        { developer: developer }
        (merge
          (default-to
            { total-projects: u0, total-credits-issued: u0, reputation-score: u100 }
            (map-get? developer-stats { developer: developer })
          )
          { total-projects: (+ (get total-projects (default-to
                               { total-projects: u0, total-credits-issued: u0, reputation-score: u100 }
                               (map-get? developer-stats { developer: developer })))
                            u1) }
        )
      )
      
      ;; Initialize category metrics
      (initialize-category-metrics category)
      (map-set category-metrics
        { category: category }
        (merge
          (default-to
            { total-projects: u0, total-credits: u0 }
            (map-get? category-metrics { category: category })
          )
          { total-projects: (+ (get total-projects (default-to
                               { total-projects: u0, total-credits: u0 }
                               (map-get? category-metrics { category: category })))
                            u1) }
        )
      )
      
      ;; Create project record
      (map-set carbon-projects
        { project-id: project-id }
        {
          name: name,
          developer: developer,
          timestamp: block-height,
          category: category,
          description: description,
          location: location,
          verified: false
        }
      )
      
      (ok true)
    )
  )
)

;; Verify emission reductions and issue credits
(define-public (verify-reductions
               (project-id (string-ascii 64))
               (period-end uint)
               (reduction-tons uint)
               (methodology (string-ascii 128)))
  (let
    ((verifier tx-sender)
     (project-data (map-get? carbon-projects { project-id: project-id }))
     (verifier-data (map-get? approved-verifiers { verifier: verifier }))
     (existing-verification (map-get? verification-records { project-id: project-id, period-end: period-end }))
     (vintage (/ period-end u10000))) ;; Extract year from period end date (YYYYMMDD)
    (begin
      ;; Validate inputs
      (asserts! (validate-project-id project-id) ERR_INVALID_DATA)
      (asserts! (validate-string-ascii methodology) ERR_INVALID_DATA)
      (asserts! (> reduction-tons u0) ERR_INVALID_PARAMETERS)
      
      ;; Check if project exists and verifier is approved
      (asserts! (is-some project-data) ERR_NOT_REGISTERED)
      (asserts! (is-some verifier-data) ERR_NO_PERMISSION)
      (asserts! (get active (unwrap! verifier-data ERR_NO_PERMISSION)) ERR_NO_PERMISSION)
      
      ;; Check if this verification period has already been processed
      (asserts! (is-none existing-verification) ERR_ALREADY_VERIFIED)
      
      ;; Record the verification
      (map-set verification-records
        { project-id: project-id, period-end: period-end }
        {
          timestamp: block-height,
          reduction-tons: reduction-tons,
          methodology: methodology,
          verifier: verifier
        }
      )
      
      ;; Issue credits to project developer
      (let ((developer (get developer (unwrap! project-data ERR_NOT_REGISTERED))))
        ;; Initialize credit balance if needed
        (initialize-credit-balance developer vintage)
        
        ;; Update credits
        (map-set credit-balances
          { owner: developer, vintage: vintage }
          { 
            amount: (+ (get amount (default-to
                        { amount: u0 }
                        (map-get? credit-balances { owner: developer, vintage: vintage })))
                     reduction-tons) 
          }
        )
        
        ;; Update developer stats
        (map-set developer-stats
          { developer: developer }
          (merge
            (default-to
              { total-projects: u0, total-credits-issued: u0, reputation-score: u100 }
              (map-get? developer-stats { developer: developer })
            )
            { 
              total-credits-issued: (+ 
                (get total-credits-issued
                  (default-to
                    { total-projects: u0, total-credits-issued: u0, reputation-score: u100 }
                    (map-get? developer-stats { developer: developer })
                  )
                )
                reduction-tons
              )
            }
          )
        )
        
        ;; Update category metrics
        (map-set category-metrics
          { category: (get category (unwrap! project-data ERR_NOT_REGISTERED)) }
          (merge
            (default-to
              { total-projects: u0, total-credits: u0 }
              (map-get? category-metrics { category: (get category (unwrap! project-data ERR_NOT_REGISTERED)) })
            )
            { 
              total-credits: (+ 
                (get total-credits
                  (default-to
                    { total-projects: u0, total-credits: u0 }
                    (map-get? category-metrics { category: (get category (unwrap! project-data ERR_NOT_REGISTERED)) })
                  )
                )
                reduction-tons
              )
            }
          )
        )
      )
      
      (ok reduction-tons)
    )
  )
)

;; Transfer carbon credits
(define-public (transfer-credits
               (recipient principal)
               (vintage uint)
               (amount uint))
  (let
    ((sender tx-sender)
     (sender-balance (default-to { amount: u0 } (map-get? credit-balances { owner: sender, vintage: vintage }))))
    (begin
      ;; Validate inputs
      (asserts! (validate-principal recipient) ERR_INVALID_DATA)
      (asserts! (> amount u0) ERR_INVALID_PARAMETERS)
      
      ;; Check if sender has sufficient credits
      (asserts! (>= (get amount sender-balance) amount) ERR_INSUFFICIENT_CREDITS)
      
      ;; Check not transferring to self
      (asserts! (not (is-eq sender recipient)) ERR_SELF_TRANSFER)
      
      ;; Initialize recipient balance if needed
      (initialize-credit-balance recipient vintage)
      
      ;; Update sender balance
      (map-set credit-balances
        { owner: sender, vintage: vintage }
        { amount: (- (get amount sender-balance) amount) }
      )
      
      ;; Update recipient balance
      (map-set credit-balances
        { owner: recipient, vintage: vintage }
        { 
          amount: (+ (get amount (default-to
                      { amount: u0 }
                      (map-get? credit-balances { owner: recipient, vintage: vintage })))
                   amount) 
        }
      )
      
      (ok true)
    )
  )
)

;; Retire carbon credits
(define-public (retire-credits
               (vintage uint)
               (amount uint)
               (retirement-reason (optional (string-utf8 256))))
  (let
    ((owner tx-sender)
     (owner-balance (default-to { amount: u0 } (map-get? credit-balances { owner: owner, vintage: vintage }))))
    (begin
      ;; Validate inputs
      (asserts! (> amount u0) ERR_INVALID_PARAMETERS)
      
      ;; Check if owner has sufficient credits
      (asserts! (>= (get amount owner-balance) amount) ERR_INSUFFICIENT_CREDITS)
      
      ;; Initialize retired credits balance if needed
      (initialize-retired-credits owner vintage)
      
      ;; Update active balance
      (map-set credit-balances
        { owner: owner, vintage: vintage }
        { amount: (- (get amount owner-balance) amount) }
      )
      
      ;; Update retired balance
      (map-set retired-credits
        { owner: owner, vintage: vintage }
        { 
          amount: (+ (get amount (default-to
                      { amount: u0 }
                      (map-get? retired-credits { owner: owner, vintage: vintage })))
                   amount) 
        }
      )
      
      (ok true)
    )
  )
)
