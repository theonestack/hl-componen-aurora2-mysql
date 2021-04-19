CloudFormation do

  Description "#{external_parameters[:component_name]} - #{external_parameters[:component_version]}"

  Condition("UseUsernameAndPassword", FnEquals(Ref(:SnapshotID), ''))
  Condition("UseSnapshotID", FnNot(FnEquals(Ref(:SnapshotID), '')))
  Condition("EnablePerformanceInsights", FnEquals(Ref(:EnablePerformanceInsights), 'true'))


  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  extra_tags = external_parameters.fetch(:extra_tags, {})
  extra_tags.each { |key,value| tags << { Key: key, Value: value } }

  secrets_manager = external_parameters.fetch(:secret_username, false)
  if secrets_manager
    SecretsManager_Secret(:SecretCredentials) do
      GenerateSecretString ({
        SecretStringTemplate: "{\"username\":\"#{secrets_manager}\"}",
        GenerateStringKey: "password",
        ExcludeCharacters: "\"@'`/\\"
      })
    end
    Output(:SecretCredentials) {
      Value(Ref(:SecretCredentials))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-Secret")
    }
  end


  security_group = external_parameters.fetch(:security_group, [])
  ip_blocks = external_parameters.fetch(:ip_blocks, [])
  EC2_SecurityGroup(:SecurityGroup) do
    VpcId Ref('VPCId')
    GroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security group' ])
    SecurityGroupIngress sg_create_rules(security_group, ip_blocks) if (!security_group.empty? && !ip_blocks.empty?)
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'security-group' ])}]
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F1000', reason: 'plan is to remove these security groups or make them conditional' }
        ]
      }
    })
  end

  Output(:SecurityGroup) {
    Value(Ref(:SecurityGroup))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-security-group")
  }

  RDS_DBSubnetGroup(:DBClusterSubnetGroup) {
    SubnetIds Ref(:SubnetIds)
    DBSubnetGroupDescription FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet group' ])
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'subnet-group' ])}]
  }

  RDS_DBClusterParameterGroup(:DBClusterParameterGroup) {
    Description FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster parameter group' ])
    Family external_parameters[:family]
    Parameters external_parameters[:cluster_parameters]
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster-parameter-group' ])}]
  }

  db_name = external_parameters.fetch(:db_name, '')
  storage_encrypted = external_parameters.fetch(:storage_encrypted, false)
  kms = external_parameters.fetch(:kms_key_id, false)
  instance_username = secrets_manager ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:username}}' ]) : FnJoin('', [ '{{resolve:ssm:', external_parameters[:master_login]['username_ssm_param'], ':1}}' ])
  instance_password = secrets_manager ? FnJoin('', [ '{{resolve:secretsmanager:', Ref(:SecretCredentials), ':SecretString:password}}' ]) : FnJoin('', [ '{{resolve:ssm-secure:', external_parameters[:master_login]['password_ssm_param'], ':1}}' ])
  engine_version = external_parameters.fetch(:engine_version, nil)
  maintenance_window = external_parameters.fetch(:maintenance_window, nil)

  RDS_DBCluster(:DBCluster) {
    Engine external_parameters[:engine]
    EngineMode external_parameters[:engine_mode]
    EngineVersion engine_version unless engine_version.nil?
    PreferredMaintenanceWindow maintenance_window unless maintenance_window.nil?
    if external_parameters[:engine_mode] == 'serverless'
      ScalingConfiguration({
        AutoPause: Ref('AutoPause'),
        MinCapacity: Ref('MinCapacity'),
        MaxCapacity: Ref('MaxCapacity'),
        SecondsUntilAutoPause: Ref('SecondsUntilAutoPause')
      })
    end
    DatabaseName db_name if !db_name.empty?
    DBClusterParameterGroupName Ref(:DBClusterParameterGroup)
    SnapshotIdentifier FnIf('UseSnapshotID',Ref(:SnapshotID), Ref('AWS::NoValue'))
    DBSubnetGroupName Ref(:DBClusterSubnetGroup)
    VpcSecurityGroupIds [ Ref(:SecurityGroup) ]
    MasterUsername  FnIf('UseUsernameAndPassword', instance_username, Ref('AWS::NoValue'))
    MasterUserPassword  FnIf('UseUsernameAndPassword', instance_password, Ref('AWS::NoValue'))
    StorageEncrypted storage_encrypted
    KmsKeyId Ref('KmsKeyId') if kms
    Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'cluster' ])}]
  }

  if external_parameters[:engine_mode] == 'provisioned'
    Condition("EnableReader", FnEquals(Ref("EnableReader"), 'true'))
    RDS_DBParameterGroup(:DBInstanceParameterGroup) {
      Description FnJoin(' ', [ Ref(:EnvironmentName), external_parameters[:component_name], 'instance parameter group' ])
      Family external_parameters[:family]
      Parameters external_parameters[:instance_parameters]
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'instance-parameter-group' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceWriter) {
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine external_parameters[:engine]
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:WriterInstanceType)
      EnablePerformanceInsights Ref('EnablePerformanceInsights')
      PerformanceInsightsRetentionPeriod FnIf('EnablePerformanceInsights', Ref('PerformanceInsightsRetentionPeriod'), Ref('AWS::NoValue'))
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'writer-instance' ])}]
    }

    RDS_DBInstance(:DBClusterInstanceReader) {
      Condition(:EnableReader)
      DBSubnetGroupName Ref(:DBClusterSubnetGroup)
      DBParameterGroupName Ref(:DBInstanceParameterGroup)
      DBClusterIdentifier Ref(:DBCluster)
      Engine external_parameters[:engine]
      PubliclyAccessible 'false'
      DBInstanceClass Ref(:ReaderInstanceType)
      EnablePerformanceInsights Ref('EnablePerformanceInsights')
      PerformanceInsightsRetentionPeriod FnIf('EnablePerformanceInsights', Ref('PerformanceInsightsRetentionPeriod'), Ref('AWS::NoValue'))
      Tags tags + [{ Key: 'Name', Value: FnJoin('-', [ Ref(:EnvironmentName), external_parameters[:component_name], 'reader-instance' ])}]
    }

    Route53_RecordSet(:DBClusterReaderRecord) {
      Condition(:EnableReader)
      HostedZoneName FnSub("#{external_parameters[:dns_format]}.")
      Name FnSub("#{external_parameters[:hostname_read_endpoint]}.#{external_parameters[:dns_format]}.")
      Type 'CNAME'
      TTL '60'
      ResourceRecords [ FnGetAtt('DBCluster','ReadEndpoint.Address') ]
    }
  end

  Route53_RecordSet(:DBHostRecord) {
    HostedZoneName FnSub("#{external_parameters[:dns_format]}.")
    Name FnSub("#{external_parameters[:hostname]}.#{external_parameters[:dns_format]}.")
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('DBCluster','Endpoint.Address') ]
  }

  registry = {}
  service_discovery = external_parameters.fetch(:service_discovery, {})

  unless service_discovery.empty?
    ServiceDiscovery_Service(:ServiceRegistry) {
      NamespaceId Ref(:NamespaceId)
      Name service_discovery['name']  if service_discovery.has_key? 'name'
      DnsConfig({
        DnsRecords: [{
          TTL: 60,
          Type: 'CNAME'
        }],
        RoutingPolicy: 'WEIGHTED'
      })
      if service_discovery.has_key? 'healthcheck'
        HealthCheckConfig service_discovery['healthcheck']
      else
        HealthCheckCustomConfig ({ FailureThreshold: (service_discovery['failure_threshold'] || 1) })
      end
    }

    ServiceDiscovery_Instance(:RegisterInstance) {
      InstanceAttributes(
        AWS_INSTANCE_CNAME: FnGetAtt('DBCluster','Endpoint.Address')
      )
      ServiceId Ref(:ServiceRegistry)
    }

    Output(:ServiceRegistry) {
      Value(Ref(:ServiceRegistry))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-CloudMapService")
    }
  end

  Output(:DBClusterId) {
    Value(Ref(:DBCluster))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-dbcluster-id")
  }

end
