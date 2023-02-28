# cloud-ids-demo

The Terraform Script will create a folder with a project in it. Follow the instructions to implement and deploy Cloud IDS (Intrusion Detection System), a next-generation advanced intrusion detection service that provides threat detection for intrusions, malware, spyware and command-and-control attacks. You will simulate multiple attacks and view the threat details in the Cloud Console. This demo uses Cloud IDS, Compute, Service Networking, and Cloud Logging.


Assign yourself the following roles if you do not already have them:
  Billing Account User,
  Folder Creator,
  Organization Role Viewer,
  Organization Viewer,
  Project Creator,
  Billing role - roles/billing.user

>> Open up Cloud shell and clone the following git repository using the command below

  git clone https://github.com/mgaur10/cloud-ids-demo.git

>> Navigate to the cloud-ids-demo folder and open up the terraform.tfvars file. 

  cd cloud-ids-demo

>> In terraform.tfvars, modify the organization_id, billing_account and proxy_access_identities strings to match your own Organization ID, Billing Account and user ID that needs IAP access to compute instance. 
Save the terraform.tfvars file and exit out of it.

>> While in the cloud-ids-demo folder, run the commands below in order. 

  terraform init

  terraform plan


  terraform apply

>> After deployment is complete, you are ready to demo!


>> After completing the demo, navigate to the automatic-storage-data-classification folder and run the command below to destroy all demo resources.

  terraform destroy






