# Storage Architecture Comparison for LLM Model Caching

## Problem Statement
vLLM models can be 20-100GB each. Without proper caching, each pod restart would re-download the entire model from HuggingFace, causing:
- Long startup times (10-30 minutes per model)
- Unnecessary bandwidth usage
- Potential HuggingFace rate limiting

## Storage Solutions Comparison

### 1. HostPath Volume (Recommended for Single Node)
```
┌─────────────────────────────────────┐
│         Dell Workstation Node        │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  /var/lib/llm-models/         │   │
│  │  (Shared Directory on Host)   │   │
│  └────────┬─────────┬───────────┘   │
│           │         │                │
│      ┌────▼───┐ ┌──▼────┐          │
│      │ Pod 1  │ │ Pod 2  │          │
│      │ Llama  │ │Mixtral │          │
│      └────────┘ └────────┘          │
└─────────────────────────────────────┘
```
**Pros:**
- Simple setup for single node
- All pods share same cache
- No storage duplication
- Models persist on host

**Cons:**
- Not portable to multi-node
- Requires host directory creation
- Less secure (host access)

**Setup:**
```yaml
hostPath:
  path: /var/lib/llm-models
  type: DirectoryOrCreate
```

### 2. Local-Path with Individual PVCs (Default k3s)
```
┌─────────────────────────────────────┐
│         Dell Workstation Node        │
│                                      │
│  ┌────────┐ ┌────────┐ ┌────────┐  │
│  │  PVC1  │ │  PVC2  │ │  PVC3  │  │
│  │ 100GB  │ │ 100GB  │ │  50GB  │  │
│  └────┬───┘ └───┬────┘ └────┬───┘  │
│       │         │            │       │
│  ┌────▼───┐ ┌──▼────┐ ┌────▼───┐  │
│  │ Pod 1  │ │ Pod 2  │ │ Pod 3  │  │
│  │ Llama  │ │Mixtral │ │DeepSeek│  │
│  └────────┘ └────────┘ └────────┘  │
└─────────────────────────────────────┘
```
**Pros:**
- Works out-of-the-box
- Each pod independent
- Standard k8s pattern

**Cons:**
- Storage duplication (same model cached multiple times)
- More disk space needed
- Can't share models between pods

**Setup:**
```yaml
accessModes:
  - ReadWriteOnce  # Only one pod can mount
storageClassName: local-path
```

### 3. Longhorn with RWX Support
```
┌─────────────────────────────────────┐
│         Dell Workstation Node        │
│                                      │
│  ┌──────────────────────────────┐   │
│  │     Longhorn Volume Manager   │   │
│  │  ┌─────────────────────────┐ │   │
│  │  │  Replicated RWX Volume  │ │   │
│  │  │      500GB Cache        │ │   │
│  │  └───┬─────────┬──────────┘ │   │
│  └──────┼─────────┼────────────┘   │
│         │         │                 │
│    ┌────▼───┐ ┌──▼────┐           │
│    │ Pod 1  │ │ Pod 2  │           │
│    │ Llama  │ │Mixtral │           │
│    └────────┘ └────────┘           │
└─────────────────────────────────────┘
```
**Pros:**
- True ReadWriteMany support
- Future multi-node ready
- Data replication/protection
- Dynamic provisioning

**Cons:**
- Additional complexity
- Resource overhead
- Requires Longhorn installation

**Setup:**
```bash
# Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# Use in PVC
accessModes:
  - ReadWriteMany
storageClassName: longhorn-rwx
```

### 4. Model Baking (Not Recommended)
```dockerfile
# Baking model into container image
FROM vllm/vllm-openai:v0.5.0
RUN huggingface-cli download meta-llama/Llama-2-7b-hf \
    --local-dir /models/llama-7b
```
**Pros:**
- No volume management
- Fast startup (model pre-loaded)

**Cons:**
- Huge images (50-100GB each)
- Slow image pulls
- Difficult updates
- Registry storage costs

## Decision Matrix

| Criteria | HostPath | Individual PVCs | Longhorn | Baked Images |
|----------|----------|-----------------|----------|--------------|
| Setup Complexity | Low | Very Low | Medium | Low |
| Storage Efficiency | High | Low | High | Very Low |
| Multi-node Support | No | No | Yes | Yes |
| Performance | High | High | Medium | High |
| Maintenance | Easy | Easy | Medium | Hard |
| **Best For** | **Single Node** | Quick Testing | Production | Never |

## Recommended Implementation

For your single Dell workstation setup:

1. **Use HostPath** for production deployment
   - Create `/var/lib/llm-models` on host
   - All pods mount this directory
   - Models downloaded once, shared by all

2. **Migration Path**: If you later need multi-node:
   - Install Longhorn
   - Migrate data from hostPath to Longhorn volume
   - Update PVC configuration

3. **Quick Testing**: Use individual PVCs
   - Accept storage duplication
   - No setup required
   - Good for proof-of-concept

## Storage Size Planning

### Model Sizes (Approximate)
- **Llama 3.1 8B**: 16GB (BF16) / 8GB (INT8)
- **Mixtral 8x7B**: 90GB (BF16) / 25GB (AWQ)
- **DeepSeek Coder**: 5GB (BF16)
- **Llama 3.1 70B**: 140GB (BF16) / 35GB (INT4)

### Recommended Allocation
- **Development**: 200GB (3-4 models)
- **Production**: 500GB (8-10 models with variants)
- **With Fine-tuning**: 1TB+ (original + fine-tuned versions)

## Implementation Checklist

- [ ] Choose storage strategy based on requirements
- [ ] Create storage directory (if using hostPath)
- [ ] Apply appropriate PV/PVC configuration
- [ ] Verify PVC is bound before deploying pods
- [ ] Test model download and caching
- [ ] Monitor disk usage
- [ ] Plan for growth/migration if needed
