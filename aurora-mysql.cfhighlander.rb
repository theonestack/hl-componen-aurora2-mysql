CfhighlanderTemplate do
  Name 'aurora-mysql'
  DependsOn 'vpc'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']
    ComponentParam 'StackOctet', isGlobal: true
    ComponentParam 'NetworkPrefix', '10', isGlobal: true
    ComponentParam 'DnsDomain'
    ComponentParam 'SnapshotID'

    if engine_mode == 'provisioned'
      ComponentParam 'WriterInstanceType'
      ComponentParam 'ReaderInstanceType'
      ComponentParam 'EnableReader', 'false'
    end

    if engine_mode == 'serverless'
      ComponentParam 'AutoPause', 'true', allowedValues: ['true', 'false']
      ComponentParam 'MaxCapacity', 2, allowedValues: [1, 2, 4, 8, 16, 32, 64, 128, 256]
      ComponentParam 'MinCapacity', 2, allowedValues: [1, 2, 4, 8, 16, 32, 64, 128, 256]
      ComponentParam 'SecondsUntilAutoPause', 3600
    end

    ComponentParam 'KmsKeyId' if defined? kms_key_id
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'

    ComponentParam 'EnablePerformanceInsights', defined?(performance_insights) ? performance_insights : false
    ComponentParam 'PerformanceInsightsRetentionPeriod', defined?(performance_insights) && defined?(insights_retention)  ? insights_retention.to_i : 7

    ComponentParam 'NamespaceId' if defined? service_discovery
  end
end
