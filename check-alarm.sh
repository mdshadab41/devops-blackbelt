aws cloudwatch describe-alarms --alarm-names devops-blackbelt-high-cpu --query "MetricAlarms[0].{State:StateValue,Threshold:Threshold}"

