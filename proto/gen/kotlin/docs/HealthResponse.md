
# HealthResponse

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **status** | [**inline**](#Status) |  |  |
| **version** | **kotlin.String** | daemon 版本 |  |
| **daemon** | [**inline**](#Daemon) |  |  |
| **platform** | **kotlin.String** |  |  |
| **uptimeSeconds** | **kotlin.Long** |  |  |
| **instances** | [**HealthResponseInstances**](HealthResponseInstances.md) |  |  [optional] |


<a id="Status"></a>
## Enum: status
| Name | Value |
| ---- | ----- |
| status | ok, degraded |


<a id="Daemon"></a>
## Enum: daemon
| Name | Value |
| ---- | ----- |
| daemon | rust, kotlin |



