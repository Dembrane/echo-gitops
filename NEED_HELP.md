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
