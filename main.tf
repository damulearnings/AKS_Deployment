#terraform {
#  required_version = ">= 1.5.0"

#  required_providers {
#    azurerm = {
#      source  = "hashicorp/azurerm"
#      # Version 4.0+ is recommended for latest OpenAI & Function App features
#      version = "~> 4.0"
#    }
#    # ADD THIS: The Time Provider
#    time = {
#      source  = "hashicorp/time"
#      version = "~> 0.11"
#    }
#  }
#}


terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    time       = { source = "hashicorp/time", version = "~> 0.11" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.24" }
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}


provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    # Required for Cognitive Services (OpenAI)
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}
provider "time" {}

resource "azurerm_resource_group" "Main" {
  name     = "RG-EDJ-Enterprise-LMS-App"
  location = "CentralUS"
}

# --- 3. Fixed AKS Cluster ---
resource "azurerm_kubernetes_cluster" "aksAz" {
  name                = "aks-clu"
  location            = azurerm_resource_group.Main.location
  resource_group_name = azurerm_resource_group.Main.name
  dns_prefix          = "aksapp"

  # Identity block must be OUTSIDE the default_node_pool
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                = "system"
    #vm_size            = "standard_b2als_v2"
    #vm_size             = "Standard_DS2_v3"
    vm_size             = "Standard_D2s_v3"
    # 1. Enable autoscaling
    #auto_scaling_enabled = true

    # 2. Define the scaling range
    #min_count            = 1
    #max_count            = 3

    # 3. Optional: Set initial node count (must be between min and max)
    node_count           = 1 
  }
  # Ensure the cluster type supports autoscaling
  # (Requires standard SKU load balancer and VirtualMachineScaleSets type)
  network_profile {
    # Add this line - "azure" is standard for AKS CNI
    network_plugin     = "azure" 
    load_balancer_sku = "standard"
  }
}



# --- 4. Fixed Secondary Node Pool ---
resource "azurerm_kubernetes_cluster_node_pool" "user_app" {
  name                  = "userapp"
  # FIXED: Reference changed from .Main.id to .aksAz.id
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aksAz.id
  vm_size               = "Standard_D2s_v3"
  node_count            = 1
  #auto_scaling_enabled   = true
  #min_count             = 1
  #max_count             = 5
   lifecycle {
    ignore_changes = [node_count]
  }
}

######################  Deploying Multiple Application ################


# --- Flux CD ---
resource "helm_release" "flux" {
  name       = "flux2"
  repository = "https://fluxcd-community.github.io/helm-charts" # Added /helm-charts
  chart      = "flux2"
  namespace  = "flux-system"
  create_namespace = true
}

# --- Istio Base & Discovery ---
resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts" # Added /charts
  chart      = "base"
  namespace  = "istio-system"
  create_namespace = true
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  depends_on = [helm_release.istio_base]
}

# --- MuleSoft Namespace (Placeholder) ---
resource "kubernetes_namespace" "mulesoft" {
  metadata {
    name = "mulesoft-runtime"
    labels = {
      istio-injection = "enabled"
    }
  }
}

resource "helm_release" "twistlock_defender" {
  name       = "twistlock-defender"
  repository = "https://paloaltonetworks.github.io/twistlock-defender-helm"
  chart      = "twistlock-defender"
  namespace  = "twistlock"
  create_namespace = true

  # These values come from your Prisma Cloud Console 
  # (Manage > Defenders > Settings)
  set {
    name  = "cluster"
    value = "aks-cluster"
  }

 # set {
 #   name  = "consoleAddr"
 #   value = "your-twistlock-console-address"
 # }

 # set_sensitive {
 #   name  = "token"
 #   value = var.twistlock_token # Store this in GitHub Secrets
 # }
}







# --- External DNS ---
#resource "helm_release" "external_dns" {
#  name       = "external-dns"
#  repository = "https://kubernetes-sigs.github.io/external-dns/"
#  chart      = "external-dns"
#  namespace  = "kube-system"

#  # 1. Increase timeout to avoid the "deadline exceeded" error
#  timeout          = 6000
#  wait             = true


#  # 2. Minimum required settings for Azure
#  set {
#    name  = "provider"
#    value = "azure"
#  }

#  set {
#    name  = "azure.resourceGroup"
#    value = azurerm_resource_group.main.name
#  }

  
  #-----------------------------#
  #set {
  #  name  = "azure.tenantId"
  #  value = "621daa10-ac93-4381-aeec-7d7491b91670"
  #}

  #set {
  #  name  = "azure.subscriptionId"
  #  #value = "074224e5-1185-47a9-958d-3c25c1df9ebc"
  #}
  #01_AMS_Agent_Management_System_Azure_Kubernetes_Cluster_deployment


#------

#  set {
#    name  = "azure.tenantId"
#    value = var.azure_tenant_id
#  }

#  set {
#    name  = "azure.subscriptionId"
#    value = var.azure_subscription_id
#  }


# THESE ARE THE MISSING KEYS CAUSING THE TIMEOUT:
#  set {
#    name  = "azure.aadClientId"
#    value = var.azure_client_id
#  }

#  set {
#    name  = "azure.aadClientSecret"
#    value = var.azure_client_secret
#  }
#}


# --- Nvidia GPU Operator ---
#resource "helm_release" "gpu_operator" {
#  name       = "gpu-operator"
#  repository = "https://helm.ngc.nvidia.com"
#  chart      = "gpu-operator"
#  namespace  = "gpu-operator"
#  create_namespace = true
#}

##################### Integration AKS + ACR ###################
# Create the Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acrscusd01" # Must be globally unique, alphanumeric
  resource_group_name = azurerm_resource_group.Main.name
  location            = azurerm_resource_group.Main.location
  sku                 = "Standard"
  admin_enabled       = true
}

# Allow AKS to pull images from ACR
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
