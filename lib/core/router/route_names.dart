/// All named routes in SoulSync.
/// Use these constants instead of raw strings.
abstract final class RouteNames {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String emailVerification = '/email-verification';
  static const String forgotPassword = '/forgot-password';
  static const String createProfile = '/create-profile';

  // Main shell
  static const String home = '/home';
  static const String chat = '/chat';
  static const String music = '/music';
  static const String safety = '/safety';
  static const String drivingMode = '/safety/driving';
  static const String connect = '/connect';
  static const String together = '/together';
  static const String memories = '/memories';
  static const String profile = '/profile';

  // Couple
  static const String createCouple = '/couple/create';
  static const String invitePartner = '/couple/invite';
  static const String acceptInvitation = '/couple/accept';
  static const String coupleStatus = '/couple/status';

  // Connect sub-routes
  static const String lovePulse = '/connect/pulse';
  static const String pulseHistory = '/connect/pulse/history';
  static const String moodCheckIn = '/connect/mood';
  static const String sharedMood = '/connect/mood/shared';

  // Memories sub-routes
  static const String memoryTimeline = '/memories/timeline';
  static const String memoryUpload = '/memories/upload';
  static const String memoryDetail = '/memories/detail';
  static const String loveLetters = '/memories/letters';
  static const String createLetter = '/memories/letters/create';

  // Together sub-routes
  static const String activityList = '/together/activities';
  static const String activitySession = '/together/session';
  static const String dailyQuestions = '/together/questions';
  static const String games = '/together/games';

  // Plans
  static const String reunionPlanner = '/plans/reunion';
  static const String milestones = '/plans/milestones';

  // Settings
  static const String settings = '/settings';
  static const String privacySettings = '/settings/privacy';
  static const String notificationSettings = '/settings/notifications';
  static const String accountSettings = '/settings/account';
  static const String deleteAccount = '/settings/account/delete';
  static const String support = '/settings/support';
  static const String subscription = '/settings/subscription';
}
