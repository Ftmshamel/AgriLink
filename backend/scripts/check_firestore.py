import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path

key = Path(__file__).resolve().parents[1] / 'data' / 'agrilink-19ea5-firebase-adminsdk-fbsvc-18585073b2.json'
cred = credentials.Certificate(str(key))
firebase_admin.initialize_app(cred, {'projectId':'agrilink-19ea5'})
db = firestore.client()

def main():
    doc = db.collection('agriData').document('main').get()
    print('agriData/main exists:', doc.exists)
    if doc.exists:
        data = doc.to_dict()
        print('counts -> users:', len(data.get('users',[])), 'crops:', len(data.get('crops',[])), 'reservations:', len(data.get('reservations',[])))
    farmers = list(db.collection('farmers').stream())
    buyers = list(db.collection('buyers').stream())
    orders = list(db.collection('orders').stream())
    print('farmers docs:', len(farmers), 'buyers docs:', len(buyers), 'orders docs:', len(orders))

if __name__ == '__main__':
    main()
