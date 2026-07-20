import json
from pathlib import Path
import argparse

def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def transform_users(farmers, buyers):
    users = []
    for f in farmers:
        users.append({
            'id': f.get('id'),
            'name': f.get('name'),
            'email': f.get('email',''),
            'phone': f.get('phone',''),
            'role': 'farmer',
            'farmName': f.get('farm_name') or f.get('farmName',''),
            'farmAddress': f.get('location', {}).get('address',''),
            'latitude': f.get('location', {}).get('lat'),
            'longitude': f.get('location', {}).get('lng'),
            'crops': f.get('crops', []),
            'photo': f.get('photo') or f"https://picsum.photos/seed/{f.get('id')}/400/300",
            'rating': f.get('rating',0),
            'createdAt': f.get('created_at') or f.get('createdAt'),
        })
    for b in buyers:
        users.append({
            'id': b.get('id'),
            'name': b.get('name'),
            'email': b.get('email',''),
            'phone': b.get('phone',''),
            'role': 'buyer',
            'address': b.get('address',''),
            'preferred_crops': b.get('preferred_crops', []),
            'createdAt': b.get('created_at') or b.get('createdAt'),
        })
    return users

def transform_crops(farmers):
    crops = []
    idx = 1
    for f in farmers:
        for crop_name in f.get('crops', []):
            crops.append({
                'id': f'crop_{idx:03d}',
                'name': crop_name,
                'ownerUserId': f.get('id'),
                'farmer': f.get('farm_name'),
                'farmerEmail': f.get('email'),
                'quantity': 100,
                'price': 100,
                'createdAt': f.get('created_at') or f.get('createdAt'),
                'photo': f"https://picsum.photos/seed/{crop_name.replace(' ', '_')}-{idx}/800/600",
            })
            idx += 1
    return crops

def transform_reservations(orders):
    res = []
    for o in orders:
        res.append({
            'id': o.get('id'),
            'buyerId': o.get('buyer_id'),
            'farmerId': o.get('farmer_id'),
            'crop': o.get('crop'),
            'qty': o.get('quantity') or o.get('qty') or 0,
            'totalPrice': o.get('total_price') or o.get('totalPrice') or 0,
            'status': o.get('status', 'placed'),
            'createdAt': o.get('order_date') or o.get('created_at'),
        })
    return res

def seed(service_account, project_id, data_dir):
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print('install firebase-admin first')
        return

    cred = credentials.Certificate(service_account)
    firebase_admin.initialize_app(cred, {'projectId': project_id})
    db = firestore.client()

    data_dir = Path(data_dir)
    farmers = load(data_dir / 'sample_farmers.json')
    buyers = load(data_dir / 'sample_buyers.json')
    orders = load(data_dir / 'sample_orders.json')

    users = transform_users(farmers, buyers)
    crops = transform_crops(farmers)
    reservations = transform_reservations(orders)

    doc_ref = db.collection('agriData').document('main')
    payload = {
        'users': users,
        'crops': crops,
        'reservations': reservations,
    }
    doc_ref.set(payload)
    print('Wrote agriData/main ->', len(users), 'users,', len(crops), 'crops,', len(reservations), 'reservations')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--service-account', required=True)
    parser.add_argument('--project-id', required=True)
    parser.add_argument('--data-dir', default=str(Path(__file__).resolve().parents[1] / 'data'))
    args = parser.parse_args()
    seed(args.service_account, args.project_id, args.data_dir)

if __name__ == '__main__':
    main()
