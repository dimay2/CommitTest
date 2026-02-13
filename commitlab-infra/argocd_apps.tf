# Define the ArgoCD Application for the User Apps (Frontend/Backend)
# This tells ArgoCD to watch the 'helm' folder in your repo and deploy it to the 'default' namespace.
resource "kubernetes_manifest" "lab_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "lab-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        # Assuming the CodeCommit repo name matches the app_name variable
        repoURL        = "https://git-codecommit.${var.aws_region}.amazonaws.com/v1/repos/${var.app_name}"
        targetRevision = "HEAD"
        path           = "helm"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
  # Required to resolve conflicts with ArgoCD controller
  field_manager {
    force_conflicts = true
  }
  
  depends_on = [helm_release.argocd]
}