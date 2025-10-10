# k6 Load Tests for Echo Participant Recording

## Single Participant Test

```bash
cd scripts/k6
k6 run participant_record_test.js
```

Optional params:
- `-e PROJECT_ID=xxx` (default: `8cda68d1-051b-43b3-b0ad-12fb7eaf58a2`)
- `-e START=0 -e END=10` (chunk range, default: 0-3)
- `-e SLEEP=30` (seconds between chunks, default: 30)

## Mass Load Test

```bash
cd scripts/k6
k6 run mass_participants_test.js -e VUS=100 -e DURATION=20
```
# smoltest
```bash
cd scripts/k6
k6 run mass_participants_test.js -e VUS=20 -e DURATION=10
```

Required:
- `-e VUS=100` (max concurrent participants)
- `-e DURATION=20` (test duration in minutes)

Optional:
- `-e PROJECT_ID=xxx` (default: `8cda68d1-051b-43b3-b0ad-12fb7eaf58a2`)
- `-e MIN_CHUNKS=4` `-e MAX_CHUNKS=10` (chunks per conversation)
- `-e SLEEP=30` (seconds between chunks, default: 30)
- `-e THINK_TIME=30` (seconds between conversations, default: 30)

**Load stages:** Ramps from 10% → 25% → 50% → 100% VUs over first 30% of duration, holds 100% for remaining 70%.

**Behavior:** Simulates real recording (30s chunk intervals). No authentication required.

## Observability

run this when running a loadtest:

```bash
    watch -n 3 'kubectl get pods -n echo-dev -o wide && echo && echo "=== HPA ===" && kubectl get hpa -n echo-dev && echo && echo "=== TOP PODS ===" && 
     kubectl top pods -n echo-dev --sort-by=memory && echo && echo "=== NODES ===" && kubectl top nodes'
```

logs: 
```bash
kubectl logs -f -n echo-dev -l app=echo,component=api --prefix=true --max-log-requests=10
```

```bash
kubectl logs -f -n echo-dev -l app=echo,component=worker-cpu --prefix=true --max-log-requests=10
```

```bash
kubectl logs -f -n echo-dev -l app=echo,component=worker --prefix=true --max-log-requests=10
```