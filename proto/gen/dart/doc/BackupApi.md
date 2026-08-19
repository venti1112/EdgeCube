# edgecube_api_client.api.BackupApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createBackupJob**](BackupApi.md#createbackupjob) | **POST** /backup/jobs | 创建备份任务
[**createBackupTarget**](BackupApi.md#createbackuptarget) | **POST** /backup/targets | 创建备份目标
[**deleteBackupJob**](BackupApi.md#deletebackupjob) | **DELETE** /backup/jobs/{jobId} | 删除备份任务
[**deleteBackupTarget**](BackupApi.md#deletebackuptarget) | **DELETE** /backup/targets/{targetId} | 删除备份目标
[**listBackupJobs**](BackupApi.md#listbackupjobs) | **GET** /backup/jobs | 备份任务列表
[**listBackupTargets**](BackupApi.md#listbackuptargets) | **GET** /backup/targets | 备份目标列表(local/FTP/SFTP)
[**triggerBackupJob**](BackupApi.md#triggerbackupjob) | **POST** /backup/jobs/{jobId}/trigger | 立即执行备份(进度走 WS backup/progress)
[**updateBackupJob**](BackupApi.md#updatebackupjob) | **PUT** /backup/jobs/{jobId} | 更新备份任务
[**updateBackupTarget**](BackupApi.md#updatebackuptarget) | **PUT** /backup/targets/{targetId} | 更新备份目标


# **createBackupJob**
> BackupJob createBackupJob(backupJob)

创建备份任务

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final BackupJob backupJob = ; // BackupJob | 

try {
    final response = api.createBackupJob(backupJob);
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->createBackupJob: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **backupJob** | [**BackupJob**](BackupJob.md)|  | 

### Return type

[**BackupJob**](BackupJob.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createBackupTarget**
> BackupTarget createBackupTarget(backupTarget)

创建备份目标

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final BackupTarget backupTarget = ; // BackupTarget | 

try {
    final response = api.createBackupTarget(backupTarget);
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->createBackupTarget: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **backupTarget** | [**BackupTarget**](BackupTarget.md)|  | 

### Return type

[**BackupTarget**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteBackupJob**
> deleteBackupJob(jobId)

删除备份任务

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final String jobId = jobId_example; // String | 

try {
    api.deleteBackupJob(jobId);
} on DioException catch (e) {
    print('Exception when calling BackupApi->deleteBackupJob: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **jobId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteBackupTarget**
> deleteBackupTarget(targetId)

删除备份目标

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final String targetId = targetId_example; // String | 

try {
    api.deleteBackupTarget(targetId);
} on DioException catch (e) {
    print('Exception when calling BackupApi->deleteBackupTarget: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **targetId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listBackupJobs**
> BuiltList<BackupJob> listBackupJobs()

备份任务列表

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();

try {
    final response = api.listBackupJobs();
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->listBackupJobs: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;BackupJob&gt;**](BackupJob.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listBackupTargets**
> BuiltList<BackupTarget> listBackupTargets()

备份目标列表(local/FTP/SFTP)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();

try {
    final response = api.listBackupTargets();
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->listBackupTargets: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;BackupTarget&gt;**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **triggerBackupJob**
> JobAccepted triggerBackupJob(jobId)

立即执行备份(进度走 WS backup/progress)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final String jobId = jobId_example; // String | 

try {
    final response = api.triggerBackupJob(jobId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->triggerBackupJob: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **jobId** | **String**|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateBackupJob**
> ErrorResponse updateBackupJob(jobId, backupJob)

更新备份任务

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final String jobId = jobId_example; // String | 
final BackupJob backupJob = ; // BackupJob | 

try {
    final response = api.updateBackupJob(jobId, backupJob);
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->updateBackupJob: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **jobId** | **String**|  | 
 **backupJob** | [**BackupJob**](BackupJob.md)|  | 

### Return type

[**ErrorResponse**](ErrorResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateBackupTarget**
> BackupTarget updateBackupTarget(targetId, backupTarget)

更新备份目标

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getBackupApi();
final String targetId = targetId_example; // String | 
final BackupTarget backupTarget = ; // BackupTarget | 

try {
    final response = api.updateBackupTarget(targetId, backupTarget);
    print(response);
} on DioException catch (e) {
    print('Exception when calling BackupApi->updateBackupTarget: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **targetId** | **String**|  | 
 **backupTarget** | [**BackupTarget**](BackupTarget.md)|  | 

### Return type

[**BackupTarget**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

