import '../core/date_utils.dart';
import '../data/app_database.dart';
import '../models/app_settings.dart';
import '../models/sale.dart';

/// ساعات العمل الافتراضية في الشهر لحساب سعر الساعة.
const double defaultWorkHoursPerMonth = 174;

class MonthSummary {
  final WorkMonthPeriod period;
  final String compensationMode;
  final double actualSalary;
  final double overtimeTotal;
  final double overtimeHours;
  final double bonusTotal;
  final double absenceHoursTotal;
  final double absenceHours;
  final double absenceHoursDeduction;
  final double salesRewards;
  final double salesArea;
  final int absenceDaysUsed;

  const MonthSummary({
    required this.period,
    required this.compensationMode,
    required this.actualSalary,
    required this.overtimeTotal,
    required this.overtimeHours,
    required this.bonusTotal,
    required this.absenceHoursTotal,
    required this.absenceHours,
    required this.absenceHoursDeduction,
    required this.salesRewards,
    required this.salesArea,
    required this.absenceDaysUsed,
  });

  bool get isCommissionOnly =>
      compensationMode == CompensationMode.commissionOnly;

  /// صافي الراتب (بدون العمولات وبدون البونص):
  /// الراتب − خصم الغياب + الإضافي.
  double get netDue => actualSalary - absenceHoursDeduction + overtimeTotal;

  /// الإجمالي العام = صافي الراتب + البونص.
  /// العمولات منفصلة تماماً ولا تدخل في الحساب الشهري أو الإجمالي العام.
  double get grandTotal => netDue + bonusTotal;
}

class SaleWithCommission {
  final Sale sale;
  final double userCommission;
  final List<SaleShare> shares;
  final String? clientName;

  const SaleWithCommission({
    required this.sale,
    required this.userCommission,
    required this.shares,
    this.clientName,
  });
}

class FinanceService {
  final AppDatabase db;

  FinanceService(this.db);

  // ---------------------------------------------------------------------------
  // القوانين الأساسية
  // ---------------------------------------------------------------------------

  double hourlyRate(AppSettings settings) {
    if (settings.isCommissionOnly) return 0;
    final rate = settings.baseSalary / defaultWorkHoursPerMonth;
    return rate.isFinite ? rate : 0;
  }

  /// المبلغ = سعر الساعة × المعامل × عدد الساعات
  double overtimeAmount(AppSettings settings, double hours) =>
      hourlyRate(settings) * settings.overtimeMultiplier * hours;

  /// سعر ساعة محدد (للوضع بدون راتب أو عند التعديل اليدوي).
  double overtimeAtRate(double rate, double hours) => rate * hours;

  /// قيمة ساعة إضافية واحدة (السعر الفعلي لكل ساعة إضافية).
  double overtimeRatePerHour(AppSettings settings) {
    if (settings.useCustomOvertimeRate) return settings.customOvertimeRate;
    return hourlyRate(settings) * settings.overtimeMultiplier;
  }

  /// خصم الغياب بالساعات = سعر الساعة × عدد الساعات (بدون معامل)
  double absenceHoursAmount(AppSettings settings, double hours) =>
      hourlyRate(settings) * hours;

  /// سعر المطبخ الكامل = المساحة × سعر المتر
  double kitchenPrice(AppSettings settings, double area) =>
      area * settings.pricePerMeter;

  /// عمولة المطبخ = السعر الكامل × نسبة العمولة
  double commissionFor(Sale sale, AppSettings settings) {
    final price = kitchenPrice(settings, sale.area);
    return price * sale.commissionRate;
  }

  /// حصة المستخدم من العمولة بناءً على نسبته في المبيعات المشتركة.
  double userShareOf(double commission, SaleShare? myShare) {
    if (myShare == null) return 0;
    return commission * myShare.sharePercentage / 100;
  }

  // ---------------------------------------------------------------------------
  // التجميع لشهر عمل
  // ---------------------------------------------------------------------------

  Future<MonthSummary> summaryFor({
    required int month,
    required int year,
    required int startDay,
    required AppSettings settings,
  }) async {
    final period = AppDateUtils.workMonthPeriod(month, year, startDay);

    final override = await db.getSalaryOverride(period.monthName, year);
    final actualSalary = settings.isCommissionOnly
        ? 0.0
        : override?.actualSalary ?? settings.baseSalary;

    final timeRecords = await db.getTimeRecords(
      workMonth: period.monthName,
      workYear: year,
    );

    double overtimeTotal = 0;
    double overtimeHours = 0;
    double bonusTotal = 0;
    double absenceHoursTotal = 0;
    double absenceHoursCount = 0;
    int absenceDaysUsed = 0;

    for (final record in timeRecords) {
      if (record.isOvertime) {
        overtimeTotal += record.totalValue;
        overtimeHours += AppDateUtils.hoursBetween(
          record.startTime ?? '',
          record.endTime ?? '',
        );
      } else if (record.isBonus) {
        bonusTotal += record.totalValue;
      } else if (record.isAbsenceHours) {
        absenceHoursTotal += record.totalValue;
        absenceHoursCount += AppDateUtils.hoursBetween(
          record.startTime ?? '',
          record.endTime ?? '',
        );
      } else if (record.isAbsenceDays) {
        absenceDaysUsed += record.daysCount;
      }
    }

    // في وضع "عمولة فقط" لا يوجد راتب يُخصم منه الغياب،
    // والأيام تبقى مسجّلة ضد العطلة فقط.
    final absenceHoursDeduction = settings.isCommissionOnly
        ? 0.0
        : absenceHoursTotal;

    final sales = await _salesFor(month: month, year: year, settings: settings);
    double salesRewards = 0;
    double salesArea = 0;
    for (final item in sales) {
      salesRewards += item.rewards;
      salesArea += item.area;
    }

    return MonthSummary(
      period: period,
      compensationMode: settings.compensationMode,
      actualSalary: actualSalary,
      overtimeTotal: overtimeTotal,
      overtimeHours: overtimeHours,
      bonusTotal: bonusTotal,
      absenceHoursTotal: absenceHoursTotal,
      absenceHours: absenceHoursCount,
      absenceHoursDeduction: absenceHoursDeduction,
      salesRewards: salesRewards,
      salesArea: salesArea,
      absenceDaysUsed: absenceDaysUsed,
    );
  }

  Future<List<({double rewards, double area})>> _salesFor({
    required int month,
    required int year,
    required AppSettings settings,
  }) async {
    final period = AppDateUtils.workMonthPeriod(
      month,
      year,
      settings.workMonthStartDay,
    );
    final sales = await db.getSales(
      workMonth: period.monthName,
      workYear: year,
    );

    final result = <({double rewards, double area})>[];
    for (final sale in sales) {
      result.add((
        rewards: await _userCommissionFor(sale, settings),
        area: sale.area,
      ));
    }
    return result;
  }

  Future<double> _userCommissionFor(Sale sale, AppSettings settings) async {
    final commission = commissionFor(sale, settings);
    if (!sale.isShared) return commission;

    final shares = await db.getSaleShares(sale.id);
    final myShare = shares
        .where((s) => s.personType == SaleShare.personMe)
        .firstOrNull;
    return userShareOf(commission, myShare);
  }

  Future<SaleWithCommission> saleWithCommission(
    Sale sale,
    AppSettings settings,
  ) async {
    final commission = commissionFor(sale, settings);

    final List<SaleShare> shares;
    final double userCommission;
    if (sale.isShared) {
      shares = await db.getSaleShares(sale.id);
      final myShare = shares
          .where((s) => s.personType == SaleShare.personMe)
          .firstOrNull;
      userCommission = userShareOf(commission, myShare);
    } else {
      // البيع الفردي: كامل العمولة للمستخدم دون الحاجة لسجلات الحصص.
      shares = const [];
      userCommission = commission;
    }

    final client = sale.clientId != null
        ? await db.getClient(sale.clientId!)
        : null;
    return SaleWithCommission(
      sale: sale,
      userCommission: userCommission,
      shares: shares,
      clientName: client?.name,
    );
  }

  /// رصيد العطلة السنوية المتبقي = الرصيد الافتراضي − مجموع أيام الغياب لسنة العمل.
  Future<int> remainingLeave(AppSettings settings, {int? workYear}) async {
    final used = await db.getTotalAbsenceDaysUsed(workYear: workYear);
    return settings.annualLeaveBalance - used;
  }
}
