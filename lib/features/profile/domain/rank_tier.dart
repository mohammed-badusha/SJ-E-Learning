enum RankTier {
  bronze('Bronze', 0, 1100),
  silver('Silver', 1100, 1300),
  gold('Gold', 1300, 1500),
  platinum('Platinum', 1500, 1700),
  diamond('Diamond', 1700, null);

  const RankTier(this.label, this.floor, this.nextAt);
  final String label;
  final int floor;
  final int? nextAt;
  static RankTier forRating(int rating) =>
      values.lastWhere((tier) => rating >= tier.floor, orElse: () => bronze);
  RankTier? get next => index == values.length - 1 ? null : values[index + 1];
  int pointsToNext(int rating) =>
      nextAt == null ? 0 : (nextAt! - rating).clamp(0, nextAt!);
  double progress(int rating) =>
      nextAt == null ? 1 : ((rating - floor) / (nextAt! - floor)).clamp(0, 1);
}
