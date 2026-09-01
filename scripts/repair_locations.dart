// A one-off CLI repair tool: printing is the interface.
// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> repairLocations() async {
  final firestore = FirebaseFirestore.instance;
  final companiesSnap = await firestore.collection('companies').get();

  for (final companyDoc in companiesSnap.docs) {
    final companyId = companyDoc.id;
    final productsRef = firestore.collection('companies').doc(companyId).collection('products');
    final holdsRef = firestore.collection('companies').doc(companyId).collection('stockHolds');
    
    // Fix products
    final productsSnap = await productsRef.get();
    for (final doc in productsSnap.docs) {
      final data = doc.data();
      bool needsUpdate = false;
      
      final locationQuantities = Map<String, dynamic>.from(data['locationQuantities'] ?? {});
      final newLocationQuantities = <String, dynamic>{};
      
      for (final entry in locationQuantities.entries) {
        String key = entry.key;
        if (key.contains('.') || key.contains('_')) {
          key = key.replaceAll('.', ' ').replaceAll('_', ' ').trim();
          needsUpdate = true;
        }
        newLocationQuantities[key] = (newLocationQuantities[key] ?? 0) + entry.value;
      }
      
      final heldLocationQuantities = Map<String, dynamic>.from(data['heldLocationQuantities'] ?? {});
      final newHeldLocationQuantities = <String, dynamic>{};
      
      for (final entry in heldLocationQuantities.entries) {
        String key = entry.key;
        if (key.contains('.') || key.contains('_')) {
          key = key.replaceAll('.', ' ').replaceAll('_', ' ').trim();
          needsUpdate = true;
        }
        newHeldLocationQuantities[key] = (newHeldLocationQuantities[key] ?? 0) + entry.value;
      }
      
      if (needsUpdate) {
        await doc.reference.update({
          'locationQuantities': newLocationQuantities,
          'heldLocationQuantities': newHeldLocationQuantities,
        });
        print('Updated product ${doc.id}');
      }
    }
    
    // Fix holds
    final holdsSnap = await holdsRef.get();
    for (final doc in holdsSnap.docs) {
      final data = doc.data();
      final location = data['location'] as String?;
      if (location != null && (location.contains('.') || location.contains('_'))) {
        final newLocation = location.replaceAll('.', ' ').replaceAll('_', ' ').trim();
        await doc.reference.update({'location': newLocation});
        print('Updated hold ${doc.id}');
      }
    }
    
    // Fix transactions
    final txRef = firestore.collection('companies').doc(companyId).collection('transactions');
    final txSnap = await txRef.get();
    for (final doc in txSnap.docs) {
      final data = doc.data();
      final location = data['location'] as String?;
      if (location != null && (location.contains('.') || location.contains('_'))) {
        final newLocation = location.replaceAll('.', ' ').replaceAll('_', ' ').trim();
        await doc.reference.update({'location': newLocation});
        print('Updated transaction ${doc.id}');
      }
    }
  }
}
