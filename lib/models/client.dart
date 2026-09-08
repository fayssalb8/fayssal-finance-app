class Client {
  final int id;
  final String name;
  final String phone;

  const Client({this.id = 0, required this.name, this.phone = ''});

  Client copyWith({String? name, String? phone}) =>
      Client(id: id, name: name ?? this.name, phone: phone ?? this.phone);

  Map<String, Object?> toMap() {
    return {if (id != 0) 'id': id, 'name': name, 'phone': phone};
  }

  factory Client.fromMap(Map<String, Object?> map) {
    return Client(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
    );
  }
}

class Colleague {
  final int id;
  final String name;

  const Colleague({this.id = 0, required this.name});

  Map<String, Object?> toMap() {
    return {if (id != 0) 'id': id, 'name': name};
  }

  factory Colleague.fromMap(Map<String, Object?> map) {
    return Colleague(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
    );
  }
}
