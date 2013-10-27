#!/bin/sh
#
# Copyright (c) 2013  1&1 Internet AG
# All rights reserved.
# Written by          Joerg Pernfuss <joerg.pernfuss@1und1.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# periodic(8) PATH does not have /usr/local/bin which we need
# for curl and par2
PATH=${PATH}:/usr/local/sbin:/usr/local/bin

backupfile=${1}
filename="$(basename ${backupfile})"
dirpath="$(dirname ${backupfile})"

# script ``configuration''
#rsa_key="/usr/local/libdata/zfs-snapshots/public.pem"
#ftp_server="ftp.backupserver.domain"
#key_fs="/path/to/tempfs/where/keys/are/generated/in"
rsa_key=""
ftp_server=""
key_fs=""
# Remove this exit once you have ``configured'' the script
exit 64

# determine commands that are not a shell built-in
rc=0
dd=`which dd`
rm=`which rm`
ls=`which ls`
ssl=`which openssl`
tar=`which tar`
curl=`which curl`
par2=`which par2`
sleep=`which sleep`

${dd:?} bs=256 count=1 if=/dev/random                \
      of=${key_fs}/${filename}.key >/dev/null 2>&1 \
      || { echo "Error generating sessionkey" 1>&2; exit 1; }
${sleep:?} 1
# we sleep one second here so ssl can reliably read the file from
# tmpfs.. (BIO read error encountered, for some reason)

${ssl:?} enc -aes-256-ofb -salt -pass file:${key_fs}/${filename}.key \
         -in ${backupfile} -out ${backupfile}.enc                    \
         || { echo "Error encrypting backup" 1>&2; exit 1; }

# if the openssl call fails, we exit later via parameter expansion
secret="$(${ssl:?} base64 -A -in ${key_fs}/${filename}.key 2>/dev/null)"

${ssl:?} dgst -sha512 -binary -hmac ${secret:?"HMAC secret not set"} \
         -out ${backupfile}.hmac ${backupfile}.enc                   \
         || { echo "Error creating HMAC" 1>&2; exit 1; }

${ssl:?} rsautl -encrypt -oaep -in ${key_fs}/${filename}.key -pubin \
         -inkey ${rsa_key} -out ${backupfile}.key.enc               \
         || { echo "Error encrypting sessionkey" 1>&2; exit 1; }

${rm:?} ${key_fs}/${filename}.key || exit 1
${rm:?} ${backupfile}             || exit 1

${tar:?} cf ${backupfile}.tar -C ${dirpath}  \
         `basename ${backupfile}.enc`        \
         `basename ${backupfile}.key.enc`    \
         `basename ${backupfile}.hmac`       \
         || { echo "Error packing files" 1>&2; exit 1; }

${rm:?} ${backupfile}.enc      || exit 1
${rm:?} ${backupfile}.key.enc  || exit 1
${rm:?} ${backupfile}.hmac     || exit 1

${par2:?} c -t+ -q -q -m512 -r3 ${backupfile}.tar \
          || { echo "Error creating parity2" 1>&2; exit 1; }

for file in `${ls:?} ${backupfile}.*`
do
  ${curl:?} -T ${file} -4 --ftp-pasv --limit-rate 50m --netrc \
            --tcp-nodelay --silent ftp://${ftp_server}/
  if [ $? -eq 0 ]
  then
    ${rm:?} ${file}
  else
    echo "FTP-Upload failed for: ${file}" 1>&2
    rc=1
  fi
done
if [ ${rc} -eq 0 ]
then
  echo "Uploaded encrypted backup ${backupfile}.tar to FTP".
fi
exit ${rc}
