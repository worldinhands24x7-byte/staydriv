#!/bin/bash

# Configuration Variables
RESOURCE_GROUP="staydriv-rg"
LOCATION="eastus"
PLAN_NAME="staydriv-plan"
APP_NAME="staydriv-app"
ACR_NAME="staydrivregistry"

echo "=== Azure Deploy Script ==="

# 1. Create a Resource Group
echo "Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# 2. Create an Azure Container Registry (ACR)
echo "Creating Container Registry..."
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true

# Get ACR credentials
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query "username" --output tsv)

# 3. Log in to ACR and push image (locally built)
echo "Logging in to ACR..."
az acr login --name $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/staydriv-app:latest -f Dockerfile .
docker push $ACR_NAME.azurecr.io/staydriv-app:latest

# 4. Create App Service Plan (Linux)
echo "Creating App Service plan..."
az appservice plan create --name $PLAN_NAME --resource-group $RESOURCE_GROUP --is-linux --sku B1

# 5. Create Web App for Containers
echo "Creating Web App..."
az webapp create --resource-group $RESOURCE_GROUP \
                 --plan $PLAN_NAME \
                 --name $APP_NAME \
                 --deployment-container-image-name $ACR_NAME.azurecr.io/staydriv-app:latest

# 6. Configure Web App environment variables
echo "Configuring environment variables..."
az webapp config appsettings set --resource-group $RESOURCE_GROUP \
                                 --name $APP_NAME \
                                 --settings WEBSITES_PORT_LIMITATOR_PORT=3000 \
                                            PORT=3000 \
                                            NODE_ENV=production

echo "=== Azure Deployment Setup Completed ==="
