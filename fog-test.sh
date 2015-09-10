#!/bin/bash
############################################################
# Run fog unit tests and live tests for hp and openstack
#
# Args 1 - live test vendors (e.g. "hp openstack")
#      2 - fog test path (e.g. tests/openstack/models/compute)
#
# Prerequisites:
# - bash, rake, gem, shindo
# - Environment vars for hp helion cloud live tests
#     $HP_TENANT_ID
#     $HP_IDENTITY_URL  # e.g. https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/
#     $HP_ACCESSKEY     # if hp_use_upass_auth_style: false (in tests/.fog)
#     $HP_SECRETKEY
# - Environment vars for openstack live tests
#     $OS_AUTH_URL      # e.g. https://10.23.71.16:5000/v2.0/
#     $OS_REGION_NAME   # e.g. regionOne
#     $OS_TENANT_NAME   # e.g. admin
#     $OS_USERNAME      # e.g. admin
#     $OS_PASSWORD      # e.g. 162d02d10dbf5e6202fde54ceac4c19b43b04eec
#
# Steps: -
#     1. Check fog path in $PWD
#     2. Clone fog repository, or cd to existing fog project
#     3. Download mpapis public key, install rvm and ruby dependencies
#     4. Configure tests/.fog for live tests
#     5. Run unit tests, then live tests (if available) recursively
#     6. Print test summary report
#
# See repos -
#     https://github.com/fog/fog
############################################################
script_source=${BASH_SOURCE[0]}
script_args=$@

# build up test environment
# args:$1 - live test vendors (optional, e.g. "hp openstack")
#      $2 - fog test module (optional, e.g. models/compute)
buildupEnv() {
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(1). Build test environment"
  echo "============================================================"
  fog_vendors="${1-openstack}"
  fog_modules="${2}"
  fog_ignores="(lb_)|(planning)"
  github_repo="https://github.com/jasonzhuyx/fog.git"
  env_jenkins=`[[ "${PWD}" =~ (/var/lib/jenkins/jobs) ]] && echo "true"`
  output_file="" # or "test.tmp"

  # get full path to this script itself
  script_file="${script_source##*/}"
  script_path="$( cd "$( echo "${script_source%/*}" )" && pwd )"

  if [[ "${PWD##*/}" == "fog" ]] && [[ -f "Rakefile" ]]; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Using current fog ..."
  elif [[ "$PWD" != "${script_path}" ]]; then
    echo "PWD= $PWD"
    echo `date +"%Y-%m-%d %H:%M:%S"` "Change to ${script_path//$PWD/}"
    cd "${script_path}"
  fi

  # if no fog repo and nor in devex-tools
  local clone=`[[ ! -f "Rakefile" ]] && echo "true"`
  local devex=`([[ "${PWD}" =~ (devex-tools/aft/fog) ]] || \
          [[ ! "${PWD}" =~ (fog) ]]) && echo "true"`
  if [[ "${devex}" == "true" ]] && [[ "${clone}" == "true" ]]; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cleaning up test environment ..."
    find . -type d -exec chmod u+w {} +
    find . -name ${output_file} -delete
    rm -rf "fog"
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cloning fog - ${github_repo} ..."
    echo "------------------------------------------------------------"
    git clone "${github_repo}"
  fi
  if [[ -f "fog/Rakefile" ]] ; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Changing to ${PWD}/fog ..."
    cd fog
    git checkout test
  fi

  configRubyEnv

  CWD_BASE="${PWD}"
  echo ""
  echo "`rake --version` - `which rake`"
  echo "------------------------------------------------------------"
  (set -o posix; set)
  echo "------------------------------------------------------------"
  if [[ "${output_file}" != "" ]]; then
    echo -e "Use: \"${output_file}\" as temporary output.\n"
  fi
  if [[ "`which rake`" == "" ]]; then
    echo "Abort: Cannot find rake."
    exit -1
  elif [[ "${PWD##*/}" != "fog" ]] && [[ ! -f "pom.xml" ]] && [[ ! -f "all/pom.xml" ]]; then
    echo "Abort: Cannot find fog in PWD= $PWD"
    exit -2
  fi
  echo -e "PWD= ${PWD}\n"

  configTestArgs
  configRubyFog
}

# install rvm and ruby application dependencies
configRubyEnv() {
  if [[ "`which rake`" == "" ]] || [[ "`which rvm`" == "" ]]; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Get mpapis public key ..."
    # iptables -I OUTPUT -p tcp --dport 11371
    # gpg2 --keyserver hkp://keys.gnupg.net --recv-keys DC0E3
    command curl -sSL https://rvm.io/mpapis.asc | gpg --import -
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Install RVM for current user ..."
    command curl -sSL https://get.rvm.io | bash -s stable --ruby
  fi

  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "Install app dependencies ..."
  bundle install
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "Listing $HOME/.rvm -"
  ls -a -l $HOME/.rvm
  echo ""
  source $HOME/.rvm/scripts/rvm
  type rvm | head -1
  gem environment
}

# configure tests/.fog for live tests
configRubyFog() {
  local fog_config_file="tests/.fog"
  if [[ ! -f "${fog_config_file}" ]]; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Configuring ${fog_config_file} ..."
    cat > "${fog_config_file}" <<!
############################################################
# Settings for Fog Live Tests
#
:default:
  :hp_auth_uri: ${helion_end_point}
  :hp_auth_version: v2.0
  :hp_avl_zone: ${helion_regioname}
  :hp_access_key: ${helion_accessKey}
  :hp_secret_key: ${helion_secretKey}
  :hp_tenant_id: ${helion_projectId}
  :hp_tenant_name: ${helion_tent_name}
  :hp_use_upass_auth_style: false
  :public_key_path: ~/.ssh/id_rsa
  :private_key_path: ~/.ssh/id_rsa.pub
  :openstack_api_key: ${openstack_password}
  :openstack_username: ${openstack_username}
  :openstack_auth_url: ${openstack_auth_url%/}/tokens
  :openstack_tenant: ${openstack_tenant}
  :openstack_region: ${openstack_region}
  :ssl_verify_peer: false
  connection_options:
    ssl_verify_peer: false
  mock: false
#
# End of Fog Live Tests Settings
############################################################
!
  fi
  echo -e "\n${fog_config_file}"
  echo "------------------------------------------------------------"
  cat  "${fog_config_file}"
  echo "------------------------------------------------------------"
  echo ""
}

# add endpoint host to $no_proxy
# args:$1 - output result (multi-lined) from previous command
configTest_NoProxy() {
  echo `date +"%Y-%m-%d %H:%M:%S"` "Checking proxy for $1 ..."
  if [[ "${HTTP_PROXY:-$http_proxy}" != "" ]] || \
     [[ "${HTTPS_PROXY:-$https_proxy}" != "" ]]; then
     if [[ "$1" =~ (https?://(.+)(:[0-9]+)\/) ]]; then
       local host="${BASH_REMATCH[2]}"
       echo `date +"%Y-%m-%d %H:%M:%S"` "Adding [$host] to no_proxy ..."
       no_proxy="${no_proxy:-localhost},${host}"
     fi
  fi
}

# initialize global configuration and settings (only run once for all tests)
configTestArgs() {
  default_tenantId="admin"
  default_username="admin"
  default_password="ca6eff5aa6c1f23a4062b164ee5a73fc62d03e86"
  default_auth_url="https://10.23.71.16:5000/v2.0/"
  default_provider="openstack"
  hpcloud_username="${HP_USERNAME:=Platform-AddIn-QA}"
  hpcloud_password="${HP_PASSWORD:=0123456789}"
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(2). Start test configurations"
  echo "============================================================"
  echo "PWD= $PWD"

  # default settings for openstack and hp providers
  configTestArgs_openstack
  configTestArgs_hpcloud

  # settings for counters of live tests and unit tests
  count_livetest=0
  count_livetest_tfiles=0
  count_livetest_bypass=0
  count_livetest_failed=0
  count_livetest_passed=0
  names_livetest=""
  sumup_unittest=""
  exitcode=0
}

# settings for HP public cloud account
configTestArgs_hpcloud() {
  helion_regioname="${HP_REGION}"
  helion_end_point="${HP_IDENTITY_URL}"
  helion_tent_name="${HP_TENANT_NAME:=Unknown}"
  helion_projectId="${HP_TENANT_ID:=Unknown}"
  helion_accessKey="${HP_ACCESSKEY:=Unknown}"
  helion_secretKey="${HP_SECRETKEY:=Unknown}"

  if [[ "${HP_IDENTITY_URL}" =~ (https://(region.+)\.identity\.hpcloudsvc\.com) ]]; then
    if [[ "${HP_REGION}" == "" ]]; then
      helion_regioname="${BASH_REMATCH[2]}"
    fi
    helion_end_point="${BASH_REMATCH[1]}"
  else
    helion_end_point="https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/"
    helion_regioname="region-a.geo-1"
  fi

  configTest_NoProxy "${helion_end_point}"
}

# settings for openstack cloud account
configTestArgs_openstack() {
  openstack_auth_url="${OS_AUTH_URL:=$default_auth_url}"
  openstack_username="${OS_USERNAME:=$default_username}"
  openstack_password="${OS_PASSWORD:=$default_password}"
  openstack_tenant="${OS_TENANT_NAME:=$default_tenantId}"
  openstack_region="${OS_REGION_NAME:=regionOne}"

  configTest_NoProxy "${openstack_auth_url}"
}

# search live tests recursively in specified or current directory
checkTests() {
  for v in ${fog_vendors}; do
    local dir_path="tests/${v}"
    if [[ "${fog_modules}" != "" ]] && \
       [[ -d "${dir_path}/${fog_modules}" ]]; then
      dir_path="${dir_path}/${fog_modules}"
    fi

    echo ""
    if [[ "${dir_path}" =~ (${fog_ignores}) ]]; then
      echo `date +"%Y-%m-%d %H:%M:%S"` "Skipping tests in [${dir_path}] ..."
      count_livetest_bypass=$((${count_livetest_bypass} + 1))
      continue
    fi

    echo `date +"%Y-%m-%d %H:%M:%S"` "Run live tests in [${dir_path}] ..."
    for test in `find "${dir_path}" -name *tests.rb 2>/dev/null`; do
      if [[ -f "${test}" ]]; then
        runLiveTest "${v}" "${test}"
      fi
    done
  done
}

# parse output from test result and update test counters
# args:$1 - output result (multi-lined) from previous command
#      $2 - provider (e.g. "openstack", or "hp")
#      $3 - test file name
parseOutput() {
  local output="$1"
  local counts=0
  local counts_errors=0 counts_failed=0 counts_passed=0
  local test_result="------------------------------------------------------------[TLDR]"
  local IFS_SAVED=$IFS

  if [[ -f "${output}" ]]; then
    while read -r line && [[ "${counts}" == "0" ]]; do
      parseOutputCounters "${line}" "$2"
    done < "${output}"
  else
    while IFS='\n' read -r line && [[ "${counts}" == "0" ]]; do
      parseOutputCounters "${line}" "$2"
    done <<< "${output}"
  fi
  IFS=$IFS_SAVED

  local t_remark=`[[ "${counts_passed}" != "${counts}" ]] && echo " *"`
  local counters="[ $counts_passed + $counts_failed] ${t_remark}"
  names_livetest="$2 : $3 ${counters}\n${names_livetest}"

  if [[ "${counts_failed}" != "0" ]] || [[ "${counts_errors}" != "0" ]] ; then
    echo "*** SEE TEST RESULT:"
    echo -e "${test_result}"
    echo -e "[/TLDR]"
  fi

  # summarizing counts for final report
  counts=$(($counts_passed + $counts_failed))
  count_livetest=$(($count_livetest + $counts))
  count_livetest_failed=$(($count_livetest_failed + $counts_failed))
  count_livetest_passed=$(($count_livetest_passed + $counts_passed))

  exitcode=$(($exitcode + $counts_failed))
  echo ""
}

# parse output from test result and update test counters
# args:$1 - output result (multi-lined) from previous command
#      $2 - provider (e.g. "openstack", or "hp")
parseOutputCounters() {
  local regexp_name="(.+) \(($2.*)\)"
  local regexp_fail="([0-9]+) failed"
  local regexp_pass="([0-9]+) succeeded"
  local regexp_test="([0-9]+) runs, ([0-9]+) assertions, ([0-9]+) failures, 0 errors, ([0-9]+) skips"
  local vendor_name=""
  local module_name=""
  local ignore_line=""

  if [[ "${1}" =~ (\[fog\]\[WARNING\]) ]] || \
     [[ "${1}" =~ (Skipping tests for) ]]; then
     ignore_line="${ignore_line}\n${1}"
  else
    if [[ "${1}" =~ ($regexp_name) ]] && [[ "${module_name}" == "" ]]; then
      module_name="${BASH_REMATCH[2]}"
      vendor_name="${BASH_REMATCH[3]}"
      echo "${1}"
    elif [[ "${1}" =~ (An error occurred) ]]; then
      counts_errors=1
    else
      local status_line="false"
      if [[ "${1}" =~ ($regexp_pass) ]]; then
        counts_passed="${BASH_REMATCH[2]}"
        status_line="true"
      fi
      if [[ "${1}" =~ ($regexp_fail) ]]; then
        counts_failed="${BASH_REMATCH[2]}"
        status_line="true"
      fi
      if [[ "${status_line}" == "true" ]]; then
        echo "${1}"
      fi
    fi
    test_result="${test_result}\n${1}"
  fi
}

# run live tests for matched vendors
# args:$1 - provider (e.g. "openstack", or "hp")
#      $2 - ruby test file
runLiveTest() {
  local provider="$1"
  local rubytest="$2"
  local test_cmd="bundle exec shindont $rubytest"
  local test_out="${output_file}"

  echo `date +"%Y-%m-%d %H:%M:%S"` "Run test ${provider} :: ${rubytest} ..."
  printf -- "%20s--- PROVIDER=$provider && ${test_cmd}\n" " "
  count_livetest_tfiles=$(($count_livetest_tfiles + 1))
  if [[ "${test_out}" == "" ]]; then
    test_out=$(PROVIDER=$provider && ${test_cmd} 2>&1)
  else
    PROVIDER=$provider && ${test_cmd} > "${test_out}" 2>&1
  fi
  parseOutput "${test_out}" "${provider}" "${rubytest##*/}"
  echo "............................................................"
  echo ""
}

# run unit tests
runUnitTests() {
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "Run unit tests ..."
  local tests_out=$(rake test 2>&1)
  local IFS_SAVED=$IFS

  while IFS='\n' read -r line; do
    if [[ ! "${line}" =~ (\[fog\]\[(WARNING)|(DEPRECATION)\]) ]]; then
      echo "${line}"
    fi
    if [[ "${line}" =~ ([0-9]+ runs, [0-9]+ assertions) ]]; then
      sumup_unittest="${line}"
    fi
  done <<< "${tests_out}"
  IFS=$IFS_SAVED
  echo ""
}

# run summary reports
runSummary() {
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "Cleaning up ..."
  rake nuke > /dev/null
  if [[ "${output_file}" != "" ]]; then find . -name ${output_file} -delete; fi

  echo ""
  if [[ "${names_livetest}" != "" ]]; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Live Tests [ #pass + #fail ]"
    echo "------------------------------------------------------------"
    echo -e "${names_livetest}" | sort | grep -v '^$'
    echo -e "\n"
  fi
  echo `date +"%Y-%m-%d %H:%M:%S"` "(*). Summary Reports"
  echo "============================================================"
  echo "             Unit Tests: ${sumup_unittest}"
  echo ""
  echo "             Live Tests: ${count_livetest}"
  echo "                  Files: ${count_livetest_tfiles}"
  echo "                Skipped: ${count_livetest_bypass}"
  echo "                Success: ${count_livetest_passed}"
  echo "                 Failed: ${count_livetest_failed}"
  echo ""
}

# run all/customized tests
buildupEnv ${script_args}

echo ""
echo `date +"%Y-%m-%d %H:%M:%S"` "(3). Run all/customized tests"
echo "============================================================"
checkTests
runUnitTests
runSummary

echo "DONE: "`[[ "${exitcode}" == "0" ]] && echo "PASSED" || echo "FAILED (${exitcode})"`

exit ${exitcode}
