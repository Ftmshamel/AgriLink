import os
import json
import argparse
from pathlib import Path

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def seed_firestore(service_account_path, project_id, data_dir):
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print("Please install firebase-admin (pip install firebase-admin)")
        return

    cred = credentials.Certificate(service_account_path)
    firebase_admin.initialize_app(cred, {"projectId": project_id})
    db = firestore.client()

    # Collections: farmers, buyers, orders
    farmers = load_json(Path(data_dir) / "sample_farmers.json")
    buyers = load_json(Path(data_dir) / "sample_buyers.json")
    orders = load_json(Path(data_dir) / "sample_orders.json")

    for f in farmers:
        doc_ref = db.collection("farmers").document(f["id"])
        doc_ref.set(f)
        print(f"Wrote farmer {f['id']}")

    for b in buyers:
        doc_ref = db.collection("buyers").document(b["id"])
        doc_ref.set(b)
        print(f"Wrote buyer {b['id']}")

    for o in orders:
        doc_ref = db.collection("orders").document(o["id"])
        doc_ref.set(o)
        print(f"Wrote order {o['id']}")

    print("Seeding complete.")


def main():
    parser = argparse.ArgumentParser(description="Seed Firestore with sample AgriLinks data")
    parser.add_argument("--service-account", required=True, help="Path to Firebase service account JSON file")
    parser.add_argument("--project-id", required=True, help="Firebase project ID")
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parents[1] / "data"), help="Directory with sample JSON files")
    args = parser.parse_args()

    if not Path(args.service_account).exists():
        print("Service account file not found:", args.service_account)
        return

    seed_firestore(args.service_account, args.project_id, args.data_dir)


if __name__ == "__main__":
    main()
