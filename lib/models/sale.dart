class SaleStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const paid = 'paid';
}

class OrderType {
  static const kitchen = 'مطبخ';
  static const dressing = 'دريسنج';
  static const closet = 'خزانة';
  static const other = 'أخرى';
}

class Sale {
  final int id;
  final String date;
  final int? clientId;
  final String orderType;
  final double area;
  final double commissionRate;
  final bool isShared;
  final String status;
  final String workMonth;
  final int workYear;

  const Sale({
    this.id = 0,
    required this.date,
    this.clientId,
    this.orderType = OrderType.kitchen,
    required this.area,
    required this.commissionRate,
    this.isShared = false,
    this.status = SaleStatus.pending,
    required this.workMonth,
    required this.workYear,
  });

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'date': date,
      'client_id': clientId,
      'order_type': orderType,
      'area': area,
      'commission_rate': commissionRate,
      'is_shared': isShared ? 1 : 0,
      'status': status,
      'work_month': workMonth,
      'work_year': workYear,
    };
  }

  factory Sale.fromMap(Map<String, Object?> map) {
    return Sale(
      id: map['id'] as int? ?? 0,
      date: map['date'] as String? ?? '',
      clientId: map['client_id'] as int?,
      orderType: map['order_type'] as String? ?? OrderType.kitchen,
      area: (map['area'] as num?)?.toDouble() ?? 0,
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0,
      isShared: (map['is_shared'] as int? ?? 0) == 1,
      status: map['status'] as String? ?? SaleStatus.pending,
      workMonth: map['work_month'] as String? ?? '',
      workYear: map['work_year'] as int? ?? 0,
    );
  }
}

class SaleShare {
  static const personMe = 'me';
  static const personColleague = 'colleague';

  final int id;
  final int saleId;
  final String personType;
  final int? colleagueId;
  final double sharePercentage;

  const SaleShare({
    this.id = 0,
    required this.saleId,
    required this.personType,
    this.colleagueId,
    required this.sharePercentage,
  });

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'sale_id': saleId,
      'person_type': personType,
      'colleague_id': colleagueId,
      'share_percentage': sharePercentage,
    };
  }

  factory SaleShare.fromMap(Map<String, Object?> map) {
    return SaleShare(
      id: map['id'] as int? ?? 0,
      saleId: map['sale_id'] as int? ?? 0,
      personType: map['person_type'] as String? ?? '',
      colleagueId: map['colleague_id'] as int?,
      sharePercentage: (map['share_percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}
