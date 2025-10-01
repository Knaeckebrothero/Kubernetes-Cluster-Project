# LLM Infrastructure Kubernetes Deployment Guide

## Overview
This deployment configuration provides production-ready Kubernetes manifests for hosting Large Language Models (LLMs) on NVIDIA L40 GPUs using vLLM as the serving framework.

## Important: Storage Configuration

**The default k3s storage (local-path) only supports ReadWriteOnce**, which means each pod needs its own PVC. Since you're running on a single node (Dell workstation), we recommend using **hostPath volumes** which allows all pods to share the same model cache directory on the host.

Run `./setup-storage.sh` and select option 1 before deploying to configure this properly.

## Architecture Components

### Storage Options

Since k3s default storage (local-path) only supports ReadWriteOnce, you have several options:

#### Option 1: HostPath (Recommended for Single Node)
- **Best for**: Your single Dell workstation setup
- Creates a directory on the host (`/var/lib/llm-models`) that all pods can access
- Simple, no additional components needed
- Models persist across pod restarts

#### Option 2: Longhorn (If you need distributed storage)
- **Best for**: Future multi-node expansion
- Provides true ReadWriteMany support
- Requires installation of Longhorn operator
- More complex but more scalable

#### Option 3: Individual PVCs (Fallback)
- **Best for**: Quick testing without setup
- Each deployment gets its own PVC
- Works with default local-path
- Duplicates models (wastes storage)

### Model Deployments

#### Small Models (Single L40 GPU)
- **Llama 3.1 8B**: General-purpose model with 32k context
- Memory: ~16-20GB VRAM at BF16 precision
- Optimized for high throughput with up to 256 concurrent sequences

#### Medium Models (Single L40 GPU with Quantization)
- **Mixtral 8x7B**: MoE architecture with 45B total parameters
- Memory: ~25-30GB VRAM with AWQ quantization
- Reduced context window (16k) for memory efficiency

#### Specialized Models
- **DeepSeek Coder V2 Lite**: Optimized for code generation
- Memory: ~5-8GB VRAM (very efficient)
- Extended 65k context for large code files

#### Multi-Instance Deployment
- Runs 3 replicas across all available L40 GPUs
- Automatic load balancing with session affinity
- Horizontal Pod Autoscaler for dynamic scaling

## Deployment Instructions

### Prerequisites
1. k3s or Kubernetes cluster with GPU support
2. NVIDIA device plugin installed
3. At least one node with NVIDIA L40 GPU
4. kubectl configured to access your cluster

### Quick Start

#### Step 1: Configure Storage
```bash
# Run the storage setup script
chmod +x setup-storage.sh
./setup-storage.sh

# Select option 1 for single-node hostPath setup
# This creates /var/lib/llm-models on your host
```

#### Step 2: Deploy Infrastructure
```bash
# Make the deployment script executable
chmod +x deploy-llm-infrastructure.sh

# Deploy all components
./deploy-llm-infrastructure.sh deploy

# Check status
./deploy-llm-infrastructure.sh status

# Perform health checks
./deploy-llm-infrastructure.sh health
```

### Manual Deployment
```bash
# Step 1: Setup storage (choose one)
# Option A: HostPath for single node (recommended)
sudo mkdir -p /var/lib/llm-models
sudo chmod 755 /var/lib/llm-models
kubectl apply -f model-cache-pvc.yaml  # Use the hostPath version

# Option B: Individual PVCs (works with default local-path)
# Edit deployments to use separate PVCs (see comments in files)

# Step 2: Deploy models
kubectl apply -f small-model-deployment.yaml
kubectl apply -f medium-model-deployment.yaml
kubectl apply -f specialized-model-deployment.yaml

# Step 3: Deploy multi-instance with load balancing
kubectl apply -f multi-instance-deployment.yaml

# Step 4: Configure ingress and monitoring
kubectl apply -f ingress-config.yaml
kubectl apply -f monitoring-config.yaml
```

## Configuration Details

### vLLM Parameters
Key parameters configured for production use:
- `GPU_MEMORY_UTILIZATION`: 0.95 (maximize GPU memory usage)
- `MAX_NUM_BATCHED_TOKENS`: Optimized per model size
- `ENABLE_PREFIX_CACHING`: Enabled for better KV cache utilization
- `DTYPE`: BF16 for L40s optimization

### Resource Allocation
Each deployment specifies:
- GPU requests/limits (1 GPU per pod)
- Memory requirements (32-64GB per pod)
- CPU allocation (8-24 cores)
- Shared memory for PyTorch operations

### Load Balancing Strategy
- Kubernetes Service with session affinity for conversation context
- Client IP-based routing with 1-hour timeout
- Supports both ClusterIP and LoadBalancer service types

## Access Patterns

### Via Ingress (Production)
```
https://llm.university.local/v1/models              # List available models
https://llm.university.local/v1/completions         # OpenAI-compatible API
https://llm.university.local/models/llama-8b/v1     # Specific model endpoint
```

### Via Port-Forward (Development)
```bash
# Access the load-balanced service
kubectl port-forward -n llm-serving svc/llama-multi-lb 8000:80

# Access specific model
kubectl port-forward -n llm-serving svc/llama-3-1-8b-service 8001:8000
```

### API Usage
```bash
# List models
curl http://localhost:8000/v1/models

# Generate completion
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-8b",
    "prompt": "Explain quantum computing in simple terms:",
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

## Monitoring

### Metrics Endpoints
- vLLM metrics: `http://<pod-ip>:8001/metrics`
- Prometheus-compatible format
- Key metrics: requests/sec, token generation rate, queue length

### Health Checks
- Liveness probe: `/health` endpoint
- Readiness probe: Ensures model is loaded
- Initial delay: 300-600s for model loading

### Grafana Dashboard
Import the provided dashboard configuration for visualizing:
- Request throughput
- Token generation rates
- GPU utilization and memory
- Queue depths
- P95 time-to-first-token

## Troubleshooting

### Common Issues

#### PVC Not Binding
```bash
# For hostPath setup, ensure the PV exists
kubectl get pv model-cache-pv

# Check if directory exists on host
ls -la /var/lib/llm-models

# For local-path (default k3s)
kubectl get storageclass

# Check PVC status
kubectl describe pvc model-cache-pvc -n llm-serving
```

#### Storage Access Issues
```bash
# If using hostPath, ensure directory permissions
sudo chmod 755 /var/lib/llm-models

# Check which storage option is configured
kubectl get pvc -n llm-serving -o wide

# Verify pods can mount the volume
kubectl describe pod <pod-name> -n llm-serving | grep -A 10 Volumes
```

#### Model Download Failures
```bash
# Check pod logs
kubectl logs -n llm-serving <pod-name>

# Verify HuggingFace token if using gated models
kubectl create secret generic hf-token \
  --from-literal=token=<your-token> \
  -n llm-serving
```

#### GPU Not Detected
```bash
# Verify NVIDIA device plugin
kubectl get pods -n kube-system | grep nvidia

# Check node labels
kubectl get nodes --show-labels | grep gpu

# Verify GPU allocation
kubectl describe node <node-name> | grep nvidia
```

#### Out of Memory Errors
- Reduce `MAX_MODEL_LEN` for smaller context windows
- Lower `GPU_MEMORY_UTILIZATION` to leave buffer
- Enable quantization (AWQ/GPTQ) for larger models
- Reduce `MAX_NUM_SEQS` for fewer concurrent requests

## Performance Tuning

### For High Throughput
- Increase `MAX_NUM_BATCHED_TOKENS`
- Increase `MAX_NUM_SEQS`
- Use larger batch sizes

### For Low Latency
- Decrease `MAX_NUM_SEQS`
- Reduce batching parameters
- Consider dedicated instances for latency-sensitive workloads

### Memory Optimization
- Use quantization (AWQ > GPTQ > INT8)
- Reduce context length
- Enable KV cache optimization features

## Security Considerations

1. **Network Policies**: Implemented to restrict pod communication
2. **TLS**: Configure certificates for production ingress
3. **Authentication**: Integrate with university SSO/LDAP
4. **Rate Limiting**: Traefik middleware configured
5. **Resource Quotas**: Set namespace limits to prevent resource exhaustion

## Maintenance

### Model Updates
```bash
# Delete pod to force re-download of latest model
kubectl delete pod -n llm-serving <pod-name>

# Or update deployment with new model version
kubectl set env deployment/llama-3-1-8b \
  MODEL=meta-llama/Meta-Llama-3.2-8B-Instruct \
  -n llm-serving
```

### Scaling
```bash
# Manual scaling
kubectl scale deployment llama-3-1-8b-multi --replicas=2 -n llm-serving

# Check HPA status
kubectl get hpa -n llm-serving
```

## Future Enhancements

1. **Implement Redis-based rate limiting** for API gateway
2. **Add guard model** for content moderation
3. **Integrate with university authentication** system
4. **Set up distributed tracing** with Jaeger
5. **Implement model A/B testing** framework
6. **Add support for fine-tuned models** with volume mounts

## Support

For issues or questions:
- Check pod logs: `kubectl logs -n llm-serving <pod-name>`
- Review events: `kubectl get events -n llm-serving`
- Monitor GPU usage: `kubectl exec -n llm-serving <pod-name> -- nvidia-smi`
