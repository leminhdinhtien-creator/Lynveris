import 'package:flutter/foundation.dart';

const appVersion = '1.0.0';
const localRelease = bool.fromEnvironment('LYNVERIS_LOCAL_RELEASE');
const allowDevelopmentHttp = !kReleaseMode || localRelease;
const compiledApiBase = String.fromEnvironment('API_BASE_URL');
const fixedServer = kReleaseMode && !localRelease && compiledApiBase != '';

String get defaultApiBase => compiledApiBase.isNotEmpty
    ? compiledApiBase
    : (allowDevelopmentHttp ? 'http://10.0.2.2:8000' : '');
