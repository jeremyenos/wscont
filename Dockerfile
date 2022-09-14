# Set up build image
FROM centos:7 AS build

RUN yum update -y && yum group install -y "Development Tools" && \
    yum install -y cmake \
                   httpd-devel \
                   libevent-devel \
                   libyaml-devel \
                   mod_wsgi \
                   numpy \
                   openssl-devel \
                   python3 \
                   python36-devel \
                   sqlite3 \
                   which \
                   make \
                   automake \
                   autoconf \
                   libtool \
                   autogen \
                   git \
		   readline-devel \
		   uuid-devel \
		   libuuid-devel \
                   && pip3 install cython pandas mod_wsgi && \
    yum clean all && \
    mkdir /source # needed for Singularity recipe conversion compatibility

WORKDIR /source

RUN git clone https://github.com/ovis-hpc/sos && \
    cd sos && \
    export PYTHON=`which python3` && \
    ./autogen.sh && \
    mkdir -p build && \
    cd build && \
    ../configure --prefix=/usr/local/sos --enable-python && \
    make -j && \
    make install && \
    cd ../.. && \
    git clone https://github.com/nick-enoent/numsos && \
    cd numsos && \
    ./autogen.sh && \
    mkdir -p build && \
    cd build && \
    ../configure --prefix=/usr/local/sos --with-sos=/usr/local/sos && \
    make -j && \
    make install

WORKDIR /source
RUN git clone https://github.com/nick-enoent/sosdb-ui && \
    cd sosdb-ui && \
    ./autogen.sh && \
    mkdir -p build && \
    cd build && \
    ../configure --prefix=/var/www/ovis_web_svcs && \
    make -j && \
    make install

WORKDIR /source
RUN git clone https://github.com/mshow34jt/vitess-grafana && \
    cd vitess-grafana && \
    ./autogen.sh && \
    mkdir -p build && \
    cd build && \
    ../configure --prefix=/var/www/ovis_web_svcs && \
    make -j && \
    make install

# Set up running image
FROM centos:7 AS runner

RUN yum update -y && \
    yum install -y python3 \
		httpd && \
    pip3 install mysql-connector cython django==2.1.0 django-cors-headers==2.1.0 pandas && \
    yum clean all

COPY --from=build /usr/local/sos /usr/local/sos
COPY --from=build /var/www/ovis_web_svcs /var/www/ovis_web_svcs
COPY --from=build /usr/local/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-x86_64-linux-gnu.so \
                  /usr/local/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-x86_64-linux-gnu.so
ADD custom /custom
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PATH=/usr/local/sos/bin:$PATH
ENV PYTHONPATH=/usr/local/sos/lib/python3.6/site-packages

WORKDIR /var/www/ovis_web_svcs
RUN ln -s /usr/local/lib64/python3.6/site-packages/mod_wsgi/server/mod_wsgi-py36.cpython-36m-x86_64-linux-gnu.so \
          /usr/lib64/httpd/modules/mod_wsgi.so && \
    echo "LoadModule wsgi_module modules/mod_wsgi.so" > /etc/httpd/conf.modules.d/10-wsgi.conf && \
    # Create convenience config folder for mapping
    mkdir -p /log /config && \
    # Create convenience log link for mapping
    ln -s /log /var/log/ovis_web_svcs && \
    rm -f /etc/httpd/logs && \
    ln -s /log /etc/httpd/logs && \
    cp /custom/settings.py /var/www/ovis_web_svcs/sosgui/settings.py && \
    touch /log/settings.log && \
    python3 manage.py migrate && \
    python3 manage.py migrate --run-syncdb && \
    echo "from sosdb_auth.models import SosdbUser; SosdbUser.objects.create_superuser('admin', 'admin@example.com', 'pass')" | python3 manage.py shell && \
    python3 manage.py collectstatic && \
    rm -f /var/www/ovis_web_svcs/sosgui/settings.py && \
    mv /var/www/ovis_web_svcs/db.sqlite3 /custom/db.sqlite3 && \
    ln -s /config/db.sqlite3 /var/www/ovis_web_svcs/db.sqlite3 && \
    ln -s /config/settings.py /var/www/ovis_web_svcs/sosgui/settings.py && \
    ln -s /config/httpd-wsgi.conf /etc/httpd/conf.d/wsgi.conf && \
    cat /etc/httpd/conf/httpd.conf \
	|sed "s/^Listen 80/Listen 8080/g" \
	|sed "s/^User.*/User apache/g" \
	|sed "s/^Group.*/Group apache/g" \
	> /custom/httpd.conf && \
    rm -f /etc/httpd/conf/httpd.conf && \
    ln -s /config/httpd.conf /etc/httpd/conf/httpd.conf && \
    chown -R apache:apache /var/www/ovis_web_svcs /run /etc/httpd/logs /var/log/ovis_web_svcs /custom && \
    chsh -s /bin/bash apache && \
    rm -f /etc/localtime && \
    #dock2sing_only /bin/mv -f /custom/init-sing.sh /custom/init.sh
    #dock2sing_only /bin/mv -f /custom/httpd-wsgi-sing.conf /custom/httpd-wsgi.conf
    chmod +x /custom/init.sh

CMD ["/bin/bash", "-c", "/custom/init.sh"]

