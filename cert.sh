#!/bin/bash
#Created by Sam Gleske
#Thu Mar  6 23:44:35 EST 2014
#Ubuntu 13.10
#Linux 3.11.0-12-generic x86_64
#GNU bash, version 4.2.45(1)-release (x86_64-pc-linux-gnu)

#debugging enable
set -e

PROGNAME="${0##*/}"
PROGVERSION="0.1.1"

#program default variables
create=false
renew=false
revoke=false
force=false

#
# ARGUMENT HANDLING
#

#Short options are one letter.  If an argument follows a short opt then put a colon (:) after it
SHORTOPTS="hvc:r:x:"
LONGOPTS="help,version,create:,renew:,revoke:,force"
usage()
{
  cat <<EOF
######################################################################
${PROGNAME} ${PROGVERSION} - MIT License by Sam Gleske

USAGE:
  ${PROGNAME} [--create|--renew|--revoke] CNAME
  ${PROGNAME} [-c|-r|-x] CNAME

DESCRIPTION:
  This program generates signed certificates in a self managed CA.  It
  may also renew or revoke certificates.

  -h,--help          Show help
  -v,--version       Show program version
  -c,--create CNAME  Create a key and CSR based on CNAME common name.
  -r,--renew CNAME   Renew a key and generate CSR based on CNAME 
                     common name.
  -x,--revoke CNAME  Renew a key and generate CSR based on CNAME 
                     common name.
  --force            Attempt to force certificate --create.

  This is part of the my_internal_ca project.
  https://github.com/sag47/my_internal_ca


EOF
}
ARGS=$(getopt -s bash --options "${SHORTOPTS}" --longoptions "${LONGOPTS}" --name "${PROGNAME}" -- "$@")
eval set -- "$ARGS"
while true; do
  case $1 in
    -h|--help)
        usage 1>&2
        exit 1
      ;;
    -v|--version)
        echo "${PROGNAME} ${PROGVERSION} - github/sag47/my_internal_ca project" 1>&2
        exit 1
      ;;
    -c|--create)
        create=true
        cname="${2}"
        shift 2
      ;;
    -r|--renew)
        renew=true
        cname="${2}"
        shift 2
      ;;
    -x|--revoke)
        revoke=true
        cname="${2}"
        shift 2
      ;;
    --force)
        force=true
      ;;
    --)
        shift
        break
      ;;
    *)
        shift
      ;;
    esac
done

#
# Program functions
#

function preflight(){
  STATUS=0
  option=0
  if ! [ -d "./certs" -a -d "./crl" -a -d "./newcerts" -a -d "./private" -a -f "./index.txt" -a -f "./openssl.my.cnf" -a -f "./serial" -a -f "./certs/myca.crt" -a -f "./private/myca.key" -a -f "./subject" ];then
    echo "cert.sh can only be run from a managed certicate authority directory." 1>&2
    exit 1
  fi
  for x in ${create} ${renew} ${revoke};do
    if ${x};then
      ((option++))
    fi
  done
  if [ "${option}" -eq "0" ];then
    echo "Must choose at least one action: --create, --renew, --revoke."
    STATUS=1
  elif [ "${option}" -gt "1" ];then
    echo "May not choose more than one action.  Only one: --create, --renew, --revoke"
    STATUS=1
  fi
  if ${renew} && [ ! -f "./private/${cname}.key" ];then
    echo "${cname}.key does not exist!"
    echo "Perhaps you need to --create a new CSR?"
    STATUS=1
  fi
  if ! ${force} && ${create} && [ -f "./private/${cname}.key" -o -f "./certs/${cname}.crt" ];then
    echo "You must revoke the old ${cname} certificate first or renew your current certificate." 1>&2
    echo "You may may force this action with --force.  This is generally not recomended."
    STATUS=1
  fi
  return ${STATUS}
}

#
# Main execution
#

#Run a preflight check on options for compatibility.
if ! preflight 1>&2;then
  echo "Command aborted due to previous errors." 1>&2
  echo "Perhaps try --help option." 1>&2
  exit 1
fi

#set the reqdir where certificate signing requests will be temporarily stored
reqdir="${reqdir:-/tmp}"
#remove trailing slash if any
reqdir="${reqdir%/}"


if ${create};then
#do some precleanup if stuff exists
rm -f "${reqdir}/${1}.csr" "./private/${1}.key" "./certs/${1}.crt"

  #echo "openssl ca -config openssl.my.cnf -revoke \"./certs/${1}.crt\"" 1>&2

#start the signing process

#grab the subject from the subject file
subj="$(head -n1 ./subject)${1}"

#generate the private key and certificate signing request
openssl req -out "${reqdir}/${1}.csr" -new -newkey rsa:2048 -nodes -subj "${subj}" -keyout "./private/${1}.key" -days 365

#sign the certificate
openssl ca -config openssl.my.cnf -policy policy_anything -out "./certs/${1}.crt" -infiles "${reqdir}/${1}.csr"

#final cleanup and security measures
rm -f "${reqdir}/${1}.csr"
chmod 644 "./certs/${1}.crt"
chmod 600 "./private/${1}.key"

#run some tests
echo "" 1>&2
echo "" 1>&2
echo "Certificate signing information..." 1>&2
openssl x509 -subject -issuer -enddate -noout -in "./certs/${1}.crt" 1>&2
echo "" 1>&2
echo "Verify certificate..." 1>&2
openssl verify -purpose sslserver -CAfile "./certs/myca.crt" "./certs/${1}.crt" 1>&2
