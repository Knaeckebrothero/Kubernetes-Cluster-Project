#!/bin/bash
# Storage Setup Script for LLM Model Caching
# Configures appropriate storage solution based on your k3s setup

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
MODEL_CACHE_DIR="/var/lib/llm-models"
NAMESPACE="llm-serving"

# Detect storage capabilities
detect_storage() {
    print_step "Detecting available storage options..."
    
    # Check for existing storage classes
    STORAGE_CLASSES=$(kubectl get storageclass -o name 2>/dev/null | wc -l)
    print_info "Found $STORAGE_CLASSES storage class(es)"
    
    # Check default storage class
    DEFAULT_SC=$(kubectl get storageclass -o json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true") | .metadata.name' 2>/dev/null)
    
    if [ -n "$DEFAULT_SC" ]; then
        print_info "Default storage class: $DEFAULT_SC"
        
        # Check if it supports RWX
        PROVISIONER=$(kubectl get storageclass $DEFAULT_SC -o jsonpath='{.provisioner}' 2>/dev/null)
        print_info "Provisioner: $PROVISIONER"
        
        case "$PROVISIONER" in
            *"local-path"*)
                print_warning "local-path provisioner detected - only supports ReadWriteOnce"
                return 1
                ;;
            *"longhorn"*)
                print_info "Longhorn detected - supports ReadWriteMany"
                return 0
                ;;
            *"nfs"*)
                print_info "NFS provisioner detected - supports ReadWriteMany"
                return 0
                ;;
            *)
                print_warning "Unknown provisioner - checking capabilities..."
                return 2
                ;;
        esac
    else
        print_warning "No default storage class found"
        return 1
    fi
}

# Setup hostPath storage (single node)
setup_hostpath() {
    print_step "Setting up hostPath storage for single-node deployment..."
    
    # Get the node name
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    print_info "Configuring storage on node: $NODE_NAME"
    
    # Create directory on the host
    print_info "Creating model cache directory: $MODEL_CACHE_DIR"
    
    # Check if we can SSH to the node or if we're running locally
    if [ -d "/" ]; then
        # We're likely on the node itself
        sudo mkdir -p $MODEL_CACHE_DIR
        sudo chmod 755 $MODEL_CACHE_DIR
        print_info "Created directory locally"
    else
        print_warning "Please manually create directory on your node:"
        echo "  sudo mkdir -p $MODEL_CACHE_DIR"
        echo "  sudo chmod 755 $MODEL_CACHE_DIR"
        read -p "Press enter when complete..."
    fi
    
    # Apply hostPath PV and PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: model-cache-pv
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: model-cache-hostpath
  hostPath:
    path: $MODEL_CACHE_DIR
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-cache-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: model-cache-hostpath
  resources:
    requests:
      storage: 500Gi
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: model-cache-hostpath
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
EOF
    
    print_info "HostPath storage configured successfully"
}

# Setup Longhorn (if desired)
setup_longhorn() {
    print_step "Setting up Longhorn for distributed storage..."
    
    read -p "Do you want to install Longhorn? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping Longhorn installation"
        return 1
    fi
    
    # Install Longhorn
    print_info "Installing Longhorn..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml
    
    # Wait for Longhorn to be ready
    print_info "Waiting for Longhorn to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
    
    # Create RWX storage class
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "1"  # Single node, so only 1 replica
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
  dataLocality: "disabled"  # Not needed for single node
  accessMode: "rwx"
EOF
    
    # Create PVC using Longhorn
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-cache-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn-rwx
  resources:
    requests:
      storage: 500Gi
EOF
    
    print_info "Longhorn storage configured successfully"
}

# Setup NFS (if available)
setup_nfs() {
    print_step "Setting up NFS storage..."
    
    read -p "Enter NFS server address (or press enter to skip): " NFS_SERVER
    if [ -z "$NFS_SERVER" ]; then
        print_info "Skipping NFS setup"
        return 1
    fi
    
    read -p "Enter NFS export path [/exports/llm-models]: " NFS_PATH
    NFS_PATH=${NFS_PATH:-/exports/llm-models}
    
    # Install NFS provisioner
    print_info "Installing NFS subdir provisioner..."
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
        --set nfs.server=$NFS_SERVER \
        --set nfs.path=$NFS_PATH \
        --set storageClass.accessModes=ReadWriteMany \
        --namespace $NAMESPACE
    
    # Create PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-cache-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 500Gi
EOF
    
    print_info "NFS storage configured successfully"
}

# Check storage setup
verify_storage() {
    print_step "Verifying storage setup..."
    
    # Check if PVC exists and is bound
    PVC_STATUS=$(kubectl get pvc model-cache-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$PVC_STATUS" = "Bound" ]; then
        print_info "✓ PVC is bound and ready"
        
        # Get PV details
        PV_NAME=$(kubectl get pvc model-cache-pvc -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
        kubectl get pv $PV_NAME
        
        return 0
    elif [ "$PVC_STATUS" = "Pending" ]; then
        print_warning "PVC is pending - checking events..."
        kubectl describe pvc model-cache-pvc -n $NAMESPACE | tail -20
        return 1
    else
        print_error "PVC not found or in unknown state"
        return 1
    fi
}

# Pre-download models
precache_models() {
    print_step "Pre-downloading models to cache..."
    
    read -p "Do you want to pre-download models now? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping model pre-download"
        return
    fi
    
    # Apply the DaemonSet for pre-caching
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: model-precache-list
  namespace: llm-serving
data:
  models.txt: |
    meta-llama/Meta-Llama-3.1-8B-Instruct
    mistralai/Mixtral-8x7B-Instruct-v0.1
    deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct
EOF
    
    print_info "Starting model pre-cache job..."
    kubectl apply -f alternative-storage-deployment.yaml
    
    # Monitor progress
    print_info "Monitoring download progress..."
    kubectl logs -f -l app=model-precacher -n $NAMESPACE
}

# Main menu
main_menu() {
    echo ""
    print_step "LLM Storage Setup Options"
    echo "1) Single-node setup with hostPath (Recommended for your setup)"
    echo "2) Install and configure Longhorn"
    echo "3) Configure NFS storage"
    echo "4) Detect and use existing storage"
    echo "5) Verify current storage setup"
    echo "6) Pre-download models"
    echo "0) Exit"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            setup_hostpath
            verify_storage
            ;;
        2)
            setup_longhorn
            verify_storage
            ;;
        3)
            setup_nfs
            verify_storage
            ;;
        4)
            if detect_storage; then
                print_info "RWX storage available - creating PVC..."
                kubectl apply -f model-cache-pvc.yaml
            else
                print_warning "No RWX storage detected - use option 1 for hostPath"
            fi
            ;;
        5)
            verify_storage
            ;;
        6)
            precache_models
            ;;
        0)
            exit 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Main execution
print_info "LLM Model Storage Configuration Script"
print_info "======================================="

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl first."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster."
    exit 1
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    print_info "Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
fi

# Run menu
while true; do
    main_menu
done
