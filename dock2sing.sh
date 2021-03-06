#!/bin/bash
uid=`id -u`
gid=`id -g`
un=`id -un`
gn=`id -gn`
singdef=./Singularity.def
initsh=./custom/init-sing.sh
httpdwsgi=./custom/httpd-wsgi-sing.conf
/bin/cp -f ./custom/init.sh $initsh
/bin/cp -f ./custom/httpd-wsgi.conf $httpdwsgi
if [ `pip3 list --user 2>/dev/null |grep -c spython` -eq 0 ] ; then
	pip3 install --user spython
fi
~/.local/bin/spython recipe Dockerfile $singdef
perl -pi -e "s/^LD_LIBRARY_PATH=/export LD_LIBRARY_PATH=/g" $singdef
perl -pi -e "s/^PATH=/export PATH=/g" $singdef
perl -pi -e "s/^PYTHONPATH=/export PYTHONPATH=/g" $singdef
perl -pi -e "s/^chown -R apache:apache/chown -R $uid:$gid/g" $singdef
perl -pi -e "s/^chown -R apache:apache/chown -R $uid:$gid/g" $initsh
perl -pi -e "s,^exec /bin/bash /bin/bash -c,exec /bin/bash -c,g" $singdef
perl -pi -e 's,^/usr/bin/su -c "/usr/sbin/httpd -D FOREGROUND" apache,/usr/sbin/httpd -D FOREGROUND,g' $initsh
perl -pi -e "s/User apache/User $un/g" $singdef
perl -pi -e "s/Group apache/Group $gn/g" $singdef
perl -pi -e "s/#dock2sing_only//g" $singdef

IDWARN=""
if [ $uid -gt 65536 ] || [ $gid -gt 65536 ] ; then
        IDWARN="Warning! UID or GID exceeds 65536. See README.md fakeroot considerations to fix /etc/sub*id files."
fi

cat <<EOF

Recommend to use a separate terminal or these instructions will scroll off screen.
Steps to build image (sif file) and start instance (example):
  Be sure to setup "fakeroot" requirements first if not there already.
    https://sylabs.io/guides/3.5/user-guide/cli/singularity_config_fakeroot.html
    e.g.:
    singularity config fakeroot --add $un
  $IDWARN
  mkdir -p ~/webservices/config ~/webservices/log
  cd <PATH>/wscont
  singularity build --fakeroot ~/webservices/ogcws.sif Singularity.def
  cd ~/webservices
  singularity instance start --bind ./config:/config,./log:/log,./log:/run ./ogcws.sif ogcws
EOF

