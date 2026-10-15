import 'package:flutter/material.dart';

/// Anamne design tokens from docs/DESIGN.md (light mode).
const paper = Color(0xFFFBFBFA);
const mist = Color(0xFFF1F1EF);
const sheet = Color(0xFFFFFFFF);
const ink = Color(0xFF37352F);
const muted = Color(0xFF787774);
const dividerSand = Color(0xFFE9E9E7);
const focusBlue = Color(0xFF2F6FEB);
const warningAmber = Color(0xFFA85D00);
const dangerRed = Color(0xFFD14343);
const hintGray = Color(0xFFB5B4B0);

ThemeData anamneTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: focusBlue, surface: paper),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(bodyMedium: TextStyle(color: ink, fontSize: 15)),
      dividerColor: dividerSand,
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
    );
