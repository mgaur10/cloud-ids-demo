/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


# Random id for naming
resource "random_string" "id" {
  length = 4
  upper   = false
  lower   = true
  number  = true
  special = false
 }

# Create the Project
resource "google_project" "demo_project" {
  project_id      = "${var.demo_project_id}${random_string.id.result}"
  name            = "Cloud IDS Demo"
  billing_account = var.billing_account
  folder_id = google_folder.terraform_solution.name
  depends_on = [
      google_folder.terraform_solution
  ]
}

# Enable the necessary API services
resource "google_project_service" "api_service" {
  for_each = toset([
    "servicenetworking.googleapis.com",
    "ids.googleapis.com",
    "logging.googleapis.com",
    "compute.googleapis.com",

  ])

  service = each.key

  project            = google_project.demo_project.project_id
  disable_on_destroy = true
  disable_dependent_services = true
}

resource "time_sleep" "wait_60_seconds_enable_service_api" {
  depends_on = [google_project_service.api_service]
  create_duration = "60s"
}


resource "google_compute_network" "cloud_ids_network" {
  project                 = google_project.demo_project.project_id
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
  depends_on = [time_sleep.wait_60_seconds_enable_service_api]
}

resource "google_compute_subnetwork" "cloud_ids_subnetwork" {
  name          = "cloud-ids-${var.ids_network_region}"
  ip_cidr_range = "192.168.10.0/24"
  region        = var.ids_network_region
  project = google_project.demo_project.project_id
  network       = google_compute_network.cloud_ids_network.self_link
  private_ip_google_access   = true 
  depends_on = [
    google_compute_network.cloud_ids_network,
  ]
}

# Setup Private IP access

resource "google_compute_global_address" "cloud_ids_ips" {
  name          = "cloud-ids-ips"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.cloud_ids_network.id
  project = google_project.demo_project.project_id
  description = "Cloud IDS Range"
  depends_on = [time_sleep.wait_60_seconds_enable_service_api]  
}
# Create Private Connection:
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.cloud_ids_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloud_ids_ips.name]
  depends_on = [time_sleep.wait_60_seconds_enable_service_api]
}

resource "null_resource" "ids_endpoint" {
  triggers = {
    network = google_compute_network.cloud_ids_network.id
  local_vpc_network_name = var.vpc_network_name 
  local_ids_network_zone = var.ids_network_zone
  project = "${data.local_file.proj_id.content}"
  
  }


  provisioner "local-exec" {
       # "./myscript add '${self.triggers.thing}'"
    command     =  "gcloud ids endpoints create cloud-ids-${var.vpc_network_name} --network=${var.vpc_network_name} --zone=${var.ids_network_zone} --severity=INFORMATIONAL --async --project ${var.demo_project_id}${random_string.id.result}"

  }

  provisioner "local-exec" {
    when        = destroy
    command     = "gcloud ids endpoints delete cloud-ids-${self.triggers.local_vpc_network_name} --zone ${self.triggers.local_ids_network_zone} --project=${self.triggers.project}"
  
  }

   depends_on = [
    time_sleep.wait_60_seconds_enable_service_api,
    google_compute_network.cloud_ids_network,
    google_compute_subnetwork.cloud_ids_subnetwork,
    google_compute_global_address.cloud_ids_ips,
    google_service_networking_connection.private_vpc_connection,
    ]
   
}

 resource "time_sleep" "wait_for_ids" {
  depends_on = [null_resource.ids_endpoint]
  create_duration = "17m"
 }

 resource "null_resource" "proj_id" {
  triggers = {
    network = google_compute_network.cloud_ids_network.id
 
 }
  provisioner "local-exec" {
    command     =  <<EOT
   echo "${var.demo_project_id}${random_string.id.result}" >> ${path.module}/proj_id.txt
    EOT
   working_dir = path.module


}
depends_on = [time_sleep.wait_60_seconds_enable_service_api]
   
}

 resource "null_resource" "forward_rule" {
  triggers = {
    network = google_compute_network.cloud_ids_network.id
 
 }
  provisioner "local-exec" {
    command     =  <<EOT
   gcloud ids endpoints describe cloud-ids-${var.vpc_network_name} --zone=${var.ids_network_zone} --project ${var.demo_project_id}${random_string.id.result} --format="value(endpointForwardingRule)" >> ${path.module}/f_rule.txt
    EOT
   working_dir = path.module
# depends_on = [time_sleep.wait_for_ids]

}
depends_on = [time_sleep.wait_for_ids]
   
}

data "local_file" "forward_rule" {
    filename = "${path.module}/f_rule.txt"
  depends_on = [null_resource.forward_rule]
}

data "local_file" "proj_id" {
    filename = "${path.module}/proj_id.txt"
  depends_on = [null_resource.proj_id]
}


resource "null_resource" "packet_mirrors" {
 triggers = {
    network = google_compute_network.cloud_ids_network.id
    local_region = var.ids_network_region
   project = "${data.local_file.proj_id.content}"

 }

  provisioner "local-exec" {
    command     =  <<EOT
    gcloud compute packet-mirrorings create cloud-ids-packet-mirroring --region=${var.ids_network_region} --network=${var.vpc_network_name} --mirrored-subnets=cloud-ids-${var.ids_network_region} --project=${var.demo_project_id}${random_string.id.result} --collector-ilb=${data.local_file.forward_rule.content}
   # export project = google_project.demo_project.project_id.value
    EOT
    working_dir = path.module
  }
  
   provisioner "local-exec" {
    when        = destroy
  command     = "gcloud compute packet-mirrorings delete cloud-ids-packet-mirroring --region=${self.triggers.local_region} --project=${self.triggers.project}"
 working_dir = path.module
 }

 depends_on = [data.local_file.forward_rule]
   
}


resource "google_compute_firewall" "allow_http_icmp" {
name = "allow-http-icmp"
network = google_compute_network.cloud_ids_network.self_link
project = google_project.demo_project.project_id
direction = "INGRESS"
allow {
    protocol = "tcp"
    ports    = ["80"]
    }
source_ranges = ["0.0.0.0/0"]
allow {
    protocol = "icmp"
    }
    depends_on = [
        google_compute_network.cloud_ids_network
    ]
}


resource "google_compute_firewall" "allow_iap_proxy" {
name = "allow-iap-proxy"
network = google_compute_network.cloud_ids_network.self_link
project = google_project.demo_project.project_id
direction = "INGRESS"
allow {
    protocol = "tcp"
    ports    = ["22"]
    }
source_ranges = ["35.235.240.0/20"]

    depends_on = [
        google_compute_network.cloud_ids_network
    ]
}


resource "google_service_account" "compute_service_account" {
  project = google_project.demo_project.project_id
  account_id   = "compute-service-account"
  display_name = "Service Account"
}

# Create Server Instance
resource "google_compute_instance" "victim_server" {
  project = google_project.demo_project.project_id
  name         = "victim-server"
  machine_type = "n2-standard-4"
  zone         = var.ids_network_zone
  shielded_instance_config {
      enable_secure_boot = true
  }
  depends_on = [
    time_sleep.wait_60_seconds_enable_service_api,
    google_compute_router_nat.nats,
    ]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
 }

  network_interface {
    network = google_compute_network.cloud_ids_network.self_link
    subnetwork = google_compute_subnetwork.cloud_ids_subnetwork.self_link
    network_ip= "192.168.10.20"
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.compute_service_account.email
    scopes = ["cloud-platform"]
  }
  metadata_startup_script = "apt-get update -y;apt-get install -y nginx;cd /var/www/html/;sudo touch eicar.file"
}

resource "time_sleep" "wait_30_seconds_victim_server" {
  depends_on = [google_compute_instance.victim_server]
  create_duration = "30s"
}


# Create Instance
resource "google_compute_instance" "attacker_server" {
  project = google_project.demo_project.project_id
  name         = "attacker-server"
  machine_type = "n2-standard-4"
  zone         =  var.ids_network_zone
 # network_ip= "192.168.10.10"
  shielded_instance_config {
      enable_secure_boot = true
  }
  depends_on = [
    time_sleep.wait_60_seconds_enable_service_api,
    google_compute_router_nat.nats,
    ]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
 }

  network_interface {
    network = google_compute_network.cloud_ids_network.self_link
    subnetwork = google_compute_subnetwork.cloud_ids_subnetwork.self_link
    network_ip= "192.168.10.10"
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.compute_service_account.email
    scopes = ["cloud-platform"]
  }
  depends_on = [
    time_sleep.wait_60_seconds_enable_service_api,
    google_compute_router_nat.ids_nats,
    time_sleep.wait_30_seconds_victim_server,
    null_resource.packet_mirrors,
    ]
metadata_startup_script = "curl http://192.168.10.20/?item=../../../../WINNT/win.ini;curl http://192.168.10.20/eicar.file;curl http://192.168.10.20/cgi-bin/../../../..//bin/cat%20/etc/passwd;curl -H 'User-Agent: () { :; }; 123.123.123.123:9999' http://172.16.10.20/cgi-bin/test-critical"
}

# Create a CloudRouter
resource "google_compute_router" "router" {
  project = google_project.demo_project.project_id
  name    = "subnet-router"
  region  = google_compute_subnetwork.cloud_ids_subnetwork.region
  network = google_compute_network.cloud_ids_network.id

  bgp {
    asn = 64514
  }
}

# Configure a CloudNAT
resource "google_compute_router_nat" "nats" {
  project = google_project.demo_project.project_id
  name                               = "nat-cloud-ids-${var.vpc_network_name}"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  depends_on = [google_compute_router.router]
}
