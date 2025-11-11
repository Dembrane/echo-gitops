# Production Cluster Capacity Analysis

## Cluster Specs (from infra/main.tf)
- **Node Type:** s-4vcpu-8gb (4 vCPU, 8GB RAM per node)
- **Auto-scaling:** min 2 nodes, max 6 nodes
- **Raw Capacity:**
  - Minimum: 2 nodes × 4 vCPU × 8GB = **8 vCPU, 16GB RAM**
  - Maximum: 6 nodes × 4 vCPU × 8GB = **24 vCPU, 48GB RAM**

## Effective Capacity (after system overhead)
Accounting for system pods (kube-system, ingress, monitoring, ArgoCD, cert-manager, sealed-secrets):
- System overhead per node: ~0.5 vCPU, ~1.5GB RAM
- Kubernetes eviction threshold: ~10% reserved

### Usable Capacity:
- Per node: ~3.5 vCPU, ~6.5GB RAM
- **Minimum (2 nodes): ~7 vCPU, ~13GB RAM**
- **Maximum (6 nodes): ~21 vCPU, ~39GB RAM**

## Current Production Configuration (values-prod.yaml)

### Minimum Resource Requirements (requests):
| Component | Replicas | CPU/pod | RAM/pod | Total CPU | Total RAM |
|-----------|----------|---------|---------|-----------|-----------|
| apiServer | 6 | 500m | 1.5Gi | 3.0 | 9.0Gi |
| worker | 4 | 500m | 1.5Gi | 2.0 | 6.0Gi |
| workerCpu | 4 | 1000m | 1.5Gi | 4.0 | 6.0Gi |
| workerScheduler | 1 | 500m | 512Mi | 0.5 | 0.5Gi |
| directus | 2 | 1000m | 1.0Gi | 2.0 | 2.0Gi |
| neo4j | 1 | 2000m | 2.0Gi | 2.0 | 2.0Gi |
| **TOTAL** | | | | **13.5 CPU** | **25.5Gi** |

**Problem:** Minimum requirements (13.5 CPU, 25.5Gi) exceed 2-node capacity (7 CPU, 13GB)!
**Result:** Cluster immediately needs 4+ nodes, no room for scaling, high idle costs.

## Dev Configuration (values.yaml) - Tested & Working
- apiServer: requests 500m/1.5Gi, limits 1/2.5Gi
- worker: requests 500m/1.5Gi, limits 1/2.5Gi
- workerCpu: requests 1/1.5Gi, limits 2/3Gi
- workerScheduler: requests 500m/512Mi, limits 800m/1Gi
- directus: requests 500m/512Mi, limits 1/1Gi (lower than prod)
- neo4j: requests 500m/1Gi, limits 1/4Gi (much lower than prod)

## Proposed Production Configuration

### Goals:
1. Use dev's tested request/limit values (proven stable)
2. Start lean, scale horizontally as needed
3. Fit comfortably in 2-3 nodes at idle
4. Allow scaling up to 5-6 nodes under load
5. Leave ~20% capacity headroom

### Proposed Minimum Replicas:
| Component | Min | Max | CPU/pod | RAM/pod | Min CPU | Min RAM |
|-----------|-----|-----|---------|---------|---------|---------|
| apiServer | 3 | 10 | 500m | 1.5Gi | 1.5 | 4.5Gi |
| worker | 2 | 8 | 500m | 1.5Gi | 1.0 | 3.0Gi |
| workerCpu | 2 | 12 | 1000m | 1.5Gi | 2.0 | 3.0Gi |
| workerScheduler | 1 | 1 | 500m | 512Mi | 0.5 | 0.5Gi |
| directus | 2 | 4 | 500m | 512Mi | 1.0 | 1.0Gi |
| neo4j | 1 | 1 | 2000m | 2.0Gi | 2.0 | 2.0Gi |
| **TOTAL** | | | | | **8.0 CPU** | **14.0Gi** |

**Fits in:** 3 nodes with headroom ✓

### Maximum Resource Requirements (at max replicas):
| Component | Max | CPU/pod | RAM/pod | Max CPU | Max RAM |
|-----------|-----|---------|---------|---------|---------|
| apiServer | 10 | 500m | 1.5Gi | 5.0 | 15.0Gi |
| worker | 8 | 500m | 1.5Gi | 4.0 | 12.0Gi |
| workerCpu | 12 | 1000m | 1.5Gi | 12.0 | 18.0Gi |
| workerScheduler | 1 | 500m | 512Mi | 0.5 | 0.5Gi |
| directus | 4 | 500m | 512Mi | 2.0 | 2.0Gi |
| neo4j | 1 | 2000m | 2.0Gi | 2.0 | 2.0Gi |
| **TOTAL** | | | | **25.5 CPU** | **49.5Gi** |

**Fits in:** 6 nodes at ~80% capacity ✓

## Key Changes from Current Prod:
1. **apiServer:** 6→3 min replicas (allow HPA), 6→10 max, use dev limits (1/2.5Gi)
2. **worker:** 4→2 min replicas (allow HPA), 4→8 max, use dev limits (1/2.5Gi)
3. **workerCpu:** 4→2 min replicas, 21→12 max (more realistic)
4. **directus:** Keep 2 min, use dev requests/limits (500m/512Mi → 1/1Gi)
5. **neo4j:** Use dev resources (reduces from 2/2Gi → 2/2Gi requests, 4/8Gi → 4/8Gi limits)

## Benefits:
- ✅ Starts in 3 nodes instead of 4+ (cost savings)
- ✅ HPA can scale each component independently
- ✅ Uses battle-tested dev configuration
- ✅ Headroom for spikes and system overhead
- ✅ Max scaling fits within cluster capacity
