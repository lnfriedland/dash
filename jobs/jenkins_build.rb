require 'net/http'
require 'json'
require 'time'

JENKINS_URI = URI.parse("https://jenkins.sandbot.io/jenkins")
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

JENKINS_AUTH = {
  'name' => 'lfriedland',
  'password' => 'abee83ccd8d91676e6bddeb8ce9fe02c'
}

# the key of this mapping must be a unique identifier for your job, the according value must be the name that is specified in jenkins
job_mapping = {
  'Sandbox-AdminApp-Lightweight Tests' => { :job => 'Automation-AdminApp-LightweightTestSuite-Development'},
  'Sandbox-Platform-Lightweight Tests' => { :job => 'Automation-Platform-LightweightTestSuite-Development'},
  'Sandbox-Platform-Nightly Tests' => { :job => 'Automation-Platform-NightlyTestSuite-Development'},
  'PhishAlarm-Deployment Tests' => { :job => 'Alarm-Tests-Integration-DeploymentTestSuite-Staging'},
  'Staging-Platform-Deployment Tests' => { :job => 'Automation-Platform-DeploymentTestSuite-Staging'},
  'Staging-Platform-Deployment Smoke Tests' => { :job => 'Automation-Platform-DeploymentSmokeTestSuite-Staging'},
  'Staging-Platform-SSO Tests' => { :job => 'Automation-Platform-SSOTestSuite-Staging'},
  'Staging-Reporting-Deployment Tests' => { :job => 'Automation-Reporting-DeploymentTestSuite-Staging'}, 
  'Feature-AdminApp-Lightweight Tests' => { :job => 'Automation-AdminApp-LightweightTestSuite-Feature'},
  'Feature-Platform-Cross Browser Tests' => { :job => 'Automation-Platform-CrossBrowserTestSuite-Feature'},
  'Feature-Platform-Lightweight Tests' => { :job => 'Automation-Platform-LightweightTestSuite-Feature'},
  'Feature-Platform-Nightly Report Integration Tests' => { :job => 'Automation-Platform-NightlyPlatformReportSuite-Feature'},
  'Feature-Platform-Nightly Tests' => { :job => 'Automation-Platform-NightlyTestSuite-Feature'},
  'Feature-Reporting-Lightweight Tests' => { :job => 'Automation-Reporting-LightweightTestSuite-Feature'},
  'Feature-Platform-SSO Tests' => { :job => 'Automation-Platform-SSOTestSuite-Feature'},
  'Project Beta:Dev-RLF Modules-Functional Tests' => { :job => 'Automation-TrainingModules-RLF-Dev-FunctionalTests'},
  'Project Beta:RC-RLF Modules-Functional Tests' => { :job => 'Automation-TrainingModules-RLF-RC-FunctionalTests'},
  'Project Beta:Dev-V2 Modules-Functional Tests' => { :job => 'Automation-TrainingModules-V2-Dev-FunctionalTests'},
  'Project Beta:RC-V2 Modules-Functional Tests' => { :job => 'Automation-TrainingModules-V2-RC-FunctionalTests'}
}

def get_number_of_failing_tests(job_name)
  info = get_json_for_job(job_name, 'lastCompletedBuild')
  info['actions'][4]['failCount']
end

def getSkippedTests(job_name)
  skipped = get_json_for_job(job_name, 'lastCompletedBuild')
  skipped['actions'][4]['skipCount']
end

def onlyOneSkip(job_name)
   amtSkip = getSkippedTests(jenkins_project[:job])
   return true if amtSkip == 1 
   return false
end

def onlyOneFail(job_name)
   amtFailed = get_number_of_failing_tests(jenkins_project[:job])
   return true if amtFailed == 1
   return false
end

def get_completion_percentage(job_name)
  build_info = get_json_for_job(job_name)
  prev_build_info = get_json_for_job(job_name, 'lastCompletedBuild')

  return 0 if not build_info["building"]
  last_duration = (prev_build_info["duration"] / 1000).round(2)
  current_duration = (Time.now.to_f - build_info["timestamp"] / 1000).round(2)
  return 99 if current_duration >= last_duration
  ((current_duration * 100) / last_duration).round(0)
end

def get_json_for_job(job_name, build = 'lastBuild')
  job_name = URI.encode(job_name)
  http = Net::HTTP.new(JENKINS_URI.host, JENKINS_URI.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(JENKINS_URI.path + "/job/#{job_name}/#{build}/api/json")
  if JENKINS_AUTH['name']
    request.basic_auth(JENKINS_AUTH['name'], JENKINS_AUTH['password'])
  end
  response = http.request(request)
  JSON.parse(response.body)
end

def get_time(job_name, build = 'lastCompletedBuild')
	build_info = get_json_for_job(job_name)
	timeUNIX = build_info["timestamp"] / 1000
	time = Time.at(timeUNIX)
	return time.strftime("Last built %m/%d at %I:%M%p")
end

job_mapping.each do |title, jenkins_project|
  current_status = nil
  failedBuilds = nil
  skippedBuilds = nil
  SCHEDULER.every '10s', :first_in => 0 do |job|
    last_status = current_status
    build_info = get_json_for_job(jenkins_project[:job])
	timeSinceLastBuild = get_time(jenkins_project[:job])
    current_status = build_info["result"]
	name = build_info["fullDisplayName"]
    if build_info["building"]
      current_status = "BUILDING"
      percent = get_completion_percentage(jenkins_project[:job])
	  buildMessage = "#{percent} % Built"
	elsif current_status == "ABORTED"
	  buildMessage = "Execution aborted"
    elsif jenkins_project[:pre_job]
      pre_build_info = get_json_for_job(jenkins_project[:pre_job])
      current_status = "PREBUILD" if pre_build_info["building"]
      percent = get_completion_percentage(jenkins_project[:pre_job])
	  buildMessage = "#{percent} % Built"
	 elsif current_status == "FAILURE" && getSkippedTests(jenkins_project[:job]) == 0 
	  failedBuilds = get_number_of_failing_tests(jenkins_project[:job])
	  failMessage = "#{failedBuilds} tests failed."	  
	 elsif current_status == "FAILURE" 
	  failedBuilds = get_number_of_failing_tests(jenkins_project[:job])
	  skippedBuilds = getSkippedTests(jenkins_project[:job])
	  failMessage = "#{failedBuilds} tests failed. #{skippedBuilds} tests skipped."
    end

    send_event(title, {
	  suiteTitle: name,
      currentResult: current_status,
      lastResult: last_status,
      timestamp: timeSinceLastBuild,
	  fails: failMessage,
      value: buildMessage
    })
  end
end
