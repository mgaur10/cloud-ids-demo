
# Create Folder in GCP Organization
resource "google_folder" "terraform_solution" {
  display_name =  "${var.folder_name}${random_string.id.result}"
  parent = "organizations/${var.organization_id}"
  
}

#Create the service Account
resource "google_service_account" "def_ser_acc" {
   project = google_project.demo_project.project_id
   account_id   = "appengine-service-account"
   display_name = "AppEngine Service Account"
 }

  resource "google_organization_iam_member" "proj_owner" {
    org_id  = var.organization_id
    role    = "roles/owner"
    member  = "serviceAccount:${google_service_account.def_ser_acc.email}"
    depends_on = [google_service_account.def_ser_acc]
  }
