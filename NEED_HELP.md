@Dembrane, @spashii needs your help!

## infra
- add Azure LLMs
- add Runpod Servvice (or use Az Serverless / Google Cloud Run)
- setup Secrets using tf
- frontend secrets managed by vercel is not ideal

## helm
- setup liveness and readiness probes for workers-* deployments (using dramatiq)
- resource optimization for values[-prod?].yaml 

## monitoring
- need better dashboards (logs per deployment, metrics per deployment)
- setup alerting rules for critical services

## protect main branch

## remove %2Cerror%2C from directus logs lol

## [2025-10-13 00:07:49,270] [PID 8] [Thread-2] [dramatiq.middleware.time_limit.TimeLimit] [WARNING] Time limit exceeded. Raising exception in worker t │
│ echo-worker-cpu-65bfd78f46-z6x2p WARNING:dramatiq.middleware.time_limit.TimeLimit:Time limit exceeded. Raising exception in worker thread 140447687100096.                            │
│ echo-worker-cpu-65bfd78f46-z6x2p [2025-10-13 00:07:49,277] [PID 8] [Thread-5] [status] [INFO] task_run_etl_pipeline.failed  - 300113                                                  │
│ echo-worker-cpu-65bfd78f46-z6x2p INFO:status:task_run_etl_pipeline.failed  - 300113                                                                                                   │
│ echo-worker-cpu-65bfd78f46-z6x2p [2025-10-13 00:07:49,356] [PID 8] [Thread-5] [status.task_run_etl_pipeline] [ERROR] 5098277  (duration: 300.113s) (started: 5098240)                 │
│ echo-worker-cpu-65bfd78f46-z6x2p ERROR:status.task_run_etl_pipeline:5098277  (duration: 300.113s) (started: 5098240)                                   