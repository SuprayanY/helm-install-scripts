#!/bin/bash

# Harbor Installation Script with Helm and Local HTTPS Domain Setup
# This script installs Harbor using Helm and configures it for local development with HTTPS

set -e

# Configuration variables
HARBOR_DOMAIN="harbor.k8s.orb.local"
HARBOR_NAMESPACE="harbor"
ADMIN_PASSWORD="Harbor@12345"
CERT_VALIDITY_DAYS=365

echo "🚢 Starting Harbor installation with Helm..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command_exists kubectl; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    echo "Read: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

if ! command_exists helm; then
    echo "❌ helm is not installed. Please install helm first."
    echo "Read: https://helm.sh/docs/intro/install/"
    exit 1
fi

if ! command_exists openssl; then
    echo "❌ openssl is not installed. Please install openssl first."
    echo "Read: https://www.openssl.org/source/"
    echo "Mac: brew install openssl"
    exit 1
fi

echo "✅ All prerequisites are satisfied."

# Create namespace
echo "📦 Creating namespace: $HARBOR_NAMESPACE"
kubectl create namespace $HARBOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Generate TLS certificate for local domain
echo "🔐 Generating TLS certificate for $HARBOR_DOMAIN..."
openssl req -x509 -nodes -days $CERT_VALIDITY_DAYS -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/C=US/ST=State/L=City/O=Harbor/CN=$HARBOR_DOMAIN" \
    -addext "subjectAltName=DNS:$HARBOR_DOMAIN,DNS:localhost,DNS:*.$HARBOR_DOMAIN,IP:127.0.0.1"

# Create TLS secret
echo "🔑 Creating TLS secret..."
kubectl create secret tls harbor-cert --key tls.key --cert tls.crt -n $HARBOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add Harbor Helm repository
echo "📚 Adding Harbor Helm repository..."
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create values file for Harbor
echo "⚙️  Creating Harbor configuration..."
cat > harbor-values.yaml << EOF
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: "harbor-cert"
      notarySecretName: "harbor-cert"
  ingress:
    hosts:
      core: $HARBOR_DOMAIN
      notary: notary.$HARBOR_DOMAIN
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

externalURL: https://$HARBOR_DOMAIN

harborAdminPassword: "$ADMIN_PASSWORD"

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 5Gi
    chartmuseum:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 5Gi
    jobservice:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 1Gi
    database:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 1Gi
    redis:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 1Gi
    trivy:
      storageClass: ""
      accessMode: ReadWriteOnce
      size: 5Gi

# Disable notary for simplicity (optional)
notary:
  enabled: false
EOF

# Install Harbor using Helm
echo "🚀 Installing Harbor with Helm..."
helm install harbor harbor/harbor -n $HARBOR_NAMESPACE -f harbor-values.yaml

echo "⏳ Waiting for Harbor pods to be ready..."
kubectl wait --for=condition=ready pod -l app=harbor -n $HARBOR_NAMESPACE --timeout=300s

# Display installation status
echo ""
echo "🎉 Harbor installation completed!"
echo ""
echo "📊 Checking Harbor status..."
echo "Pods:"
kubectl get pods -n $HARBOR_NAMESPACE
echo ""
echo "Services:"
kubectl get svc -n $HARBOR_NAMESPACE
echo ""
echo "Ingress:"
kubectl get ingress -n $HARBOR_NAMESPACE
echo ""

# Setup instructions for local domain
echo "🌐 Local Domain Setup Instructions:"
echo "=================================="
echo ""
echo "1. ✅ Add the following entry to your /etc/hosts file:"
echo "   127.0.0.1 $HARBOR_DOMAIN"
echo "   127.0.0.1 notary.$HARBOR_DOMAIN"
echo ""
echo "2. 🚀 If you're using Docker Desktop or Minikube, you may need to:"
echo "   - For Docker Desktop: Use 'host.docker.internal' instead of '127.0.0.1'"
echo "   - For Minikube: Run 'minikube tunnel' in a separate terminal"
echo ""
echo "3. Harbor will be available at:"
echo "   - Web UI: https://$HARBOR_DOMAIN"
echo "   - Username: admin"
echo "   - Password: $ADMIN_PASSWORD"
echo ""
echo "4. 🐳 To use Harbor with Docker:"
echo "   - Login: docker login $HARBOR_DOMAIN"
echo "   - Push image: docker tag your-image $HARBOR_DOMAIN/project-name/image-name"
echo "   - Pull image: docker pull $HARBOR_DOMAIN/project-name/image-name"
echo ""
echo "5. 🔐 To trust the self-signed certificate:"
echo "   - Copy tls.crt to your system's trusted certificates"
echo "   - Or use '--insecure-registry' flag with Docker"
echo "   - Or add $HARBOR_DOMAIN to Docker's insecure registries"
echo ""
echo "📝 Note: If you are using OrbStack, it automatically handles SSL termination and domain resolution"
echo "   for *.k8s.orb.local domains, making local development seamless!"
echo ""

# Cleanup certificate files (optional)
read -p "Do you want to remove the certificate files (tls.key, tls.crt)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f tls.key tls.crt
    echo "✅ Certificate files removed."
else
    echo "📁 Certificate files kept for reference."
fi

echo ""
echo "🎯 Harbor installation script completed successfully!" 
