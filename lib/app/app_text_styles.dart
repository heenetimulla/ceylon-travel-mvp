import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  const AppTextStyles._();
  static const title = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.charcoal,
  );
  static const section = TextStyle(
    fontSize: 21,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.charcoal,
  );
  static const cardTitle = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.charcoal,
  );
  static const body = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: AppColors.charcoal,
  );
  static const secondary = TextStyle(
    fontSize: 14,
    height: 1.5,
    color: AppColors.secondary,
  );
  static const bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.charcoal,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.secondary,
  );
  static const button = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const status = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );
  static const onOcean = TextStyle(
    fontSize: 14,
    height: 1.5,
    color: AppColors.onOcean,
  );
  static const error = TextStyle(
    fontSize: 14,
    height: 1.5,
    color: AppColors.error,
  );
  static const hero = TextStyle(
    fontSize: 26,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: AppColors.surface,
  );
}
