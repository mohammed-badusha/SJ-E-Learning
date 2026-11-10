enum RankTier {
  bronze('Bronze', 0, 1000),
  silver('Silver', 1000, 3000),
  gold('Gold', 3000, 6000),
  platinum('Platinum', 6000, 10000),
  diamond('Diamond', 10000, null);

  const RankTier(this.label, this.floor, this.nextAt);
  final String label;
  final int floor;
  final int? nextAt;
  String get rangeLabel => switch (this) {
    bronze => '0–999',
    silver => '1,000–2,999',
    gold => '3,000–5,999',
    platinum => '6,000–9,999',
    diamond => '10,000+',
  };
  static RankTier forTrophies(int trophies) =>
      values.lastWhere((tier) => trophies >= tier.floor, orElse: () => bronze);
  static RankTier forRating(int rating) => forTrophies(rating);
  RankTier? get next => index == values.length - 1 ? null : values[index + 1];
  int pointsToNext(int rating) =>
      nextAt == null ? 0 : (nextAt! - rating).clamp(0, nextAt!);
  double progress(int rating) =>
      nextAt == null ? 1 : ((rating - floor) / (nextAt! - floor)).clamp(0, 1);
  double progressAt(int trophies) => trophies < floor
      ? 0
      : nextAt == null || trophies >= nextAt!
      ? 1
      : ((trophies - floor) / (nextAt! - floor)).clamp(0, 1);
}
