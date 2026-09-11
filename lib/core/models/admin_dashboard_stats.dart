import 'support_request.dart';

class AdminDashboardStats {
  const AdminDashboardStats({required this.totalUsers, required this.totalDrivers,
    required this.totalTourists, required this.totalTrips, required this.openTrips,
    required this.activeTrips, required this.completedTrips, required this.openSupportRequests});

  static const activeStatuses = ['accepted', 'start_requested', 'in_progress', 'end_requested'];
  final int totalUsers, totalDrivers, totalTourists, totalTrips;
  final int openTrips, activeTrips, completedTrips, openSupportRequests;

  Map<String, int> get cards => {
    'Total Users': totalUsers,
    'Total Drivers': totalDrivers,
    'Total Tourist/User Accounts': totalTourists,
    'Total Trips': totalTrips,
    'Open Trips': openTrips,
    'Active Trips': activeTrips,
    'Completed Trips': completedTrips,
    'Open Support Requests': openSupportRequests,
  };
}

class AdminDashboardData {
  const AdminDashboardData({required this.stats, required this.recentSupport});
  final AdminDashboardStats stats;
  final List<SupportRequest> recentSupport;
}
