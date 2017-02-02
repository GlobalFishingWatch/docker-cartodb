FROM ubuntu:12.04
RUN locale-gen en_US.UTF-8 &&\
	update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
RUN apt-get update &&\
apt-get install -q -y autoconf binutils-doc bison build-essential flex

#git
RUN apt-get install -q -y git

#apt tools
RUN apt-get install -q -y python-software-properties

#postgresql
RUN add-apt-repository ppa:cartodb/postgresql-9.5 && apt-get update

#client packages
RUN apt-get install -q -y libpq5 \
                     libpq-dev \
                     postgresql-client-9.5 \
                     postgresql-client-common
#server packages
RUN apt-get install -q -y postgresql-9.5 \
                     postgresql-contrib-9.5 \
                     postgresql-server-dev-9.5 \
                     postgresql-plpython-9.5

#PostgreSQL Config
RUN sed -i 's/\(peer\|md5\)/trust/' /etc/postgresql/9.5/main/pg_hba.conf 

#create users
RUN service postgresql start && \
createuser publicuser --no-createrole --no-createdb --no-superuser -U postgres && \
createuser tileuser --no-createrole --no-createdb --no-superuser -U postgres && \
service postgresql stop

#carto postgres extension
RUN git clone https://github.com/CartoDB/cartodb-postgresql.git &&\
cd cartodb-postgresql &&\
PGUSER=postgres make install

#GIS dependencies
RUN apt-get upgrade -q -y && add-apt-repository ppa:cartodb/gis && apt-get update &&\
 apt-get install -q -y proj proj-bin proj-data libproj-dev &&\ 
 apt-get install -q -y libjson0 libjson0-dev python-simplejson &&\ 
 apt-get install -q -y libgeos-c1v5 libgeos-dev &&\ 
 apt-get install -q -y gdal-bin libgdal1-dev libgdal-dev &&\
 apt-get install -q -y gdal2.1-static-bin

#postgis
RUN apt-get -q -y install libxml2-dev &&\
apt-get install -q -y liblwgeom-2.2.2 postgis postgresql-9.5-postgis-2.2 postgresql-9.5-postgis-scripts

#postgis setup
RUN service postgresql start && \
  createdb -T template0 -O postgres -U postgres -E UTF8 template_postgis &&\
  psql -U postgres template_postgis -c 'CREATE EXTENSION postgis;CREATE EXTENSION postgis_topology;' &&\
  ldconfig &&\
  service postgresql stop

#redis
RUN add-apt-repository ppa:cartodb/redis && apt-get update

RUN apt-get install -q -y redis-server

#nodejs
RUN add-apt-repository ppa:cartodb/nodejs-010 && apt-get update &&\
apt-get install -q -y nodejs

#SQL API
RUN git clone git://github.com/CartoDB/CartoDB-SQL-API.git &&\
cd CartoDB-SQL-API &&\
git checkout master &&\
npm install 

#MAPS API:
RUN git clone git://github.com/CartoDB/Windshaft-cartodb.git &&\
cd Windshaft-cartodb &&\
git checkout 2.87.3 &&\
apt-get install -q -y libpango1.0-dev &&\
npm install

#Ruby
RUN apt-get install -q -y wget &&\
wget -O ruby-install-0.5.0.tar.gz https://github.com/postmodern/ruby-install/archive/v0.5.0.tar.gz &&\
tar -xzvf ruby-install-0.5.0.tar.gz &&\
cd ruby-install-0.5.0/ &&\
make install

RUN apt-get -q -y install libreadline6-dev openssl &&\
ruby-install ruby 2.2.3 

ENV PATH=$PATH:/opt/rubies/ruby-2.2.3/bin 

RUN gem install bundler &&\
gem install compass

#Carto Editor
RUN git clone --recursive https://github.com/CartoDB/cartodb.git &&\
cd cartodb &&\
wget  -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py &&\
python /tmp/get-pip.py &&\
apt-get install -q -y python-all-dev &&\
apt-get install -q -y imagemagick unp zip &&\
RAILS_ENV=development bundle install &&\
npm install 

ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal
ENV PATH=$PATH:/usr/include/gdal

RUN cd cartodb && pip install --no-use-wheel -r python_requirements.txt


#Config Files
ADD ./config/CartoDB-dev.js \
      /CartoDB-SQL-API/config/environments/development.js
ADD ./config/WS-dev.js \
      /Windshaft-cartodb/config/environments/development.js
ADD ./config/app_config.yml /cartodb/config/app_config.yml
ADD ./config/database.yml /cartodb/config/database.yml

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8


RUN cd cartodb &&\
    npm install npm@2.14.9 -g &&\
    npm -v &&\
    export PATH=$PATH:$PWD/node_modules/grunt-cli/bin &&\
    bundle install &&\
    bundle exec grunt --environment development

RUN service postgresql start && service redis-server start &&\
    cd cartodb &&\
    RAILS_ENV=development bundle exec rake db:create &&\ 
    RAILS_ENV=development bundle exec rake db:migrate &&\
    service postgresql stop && service redis-server stop

ADD ./create_dev_user /cartodb/script/create_dev_user
ADD ./setup_organization.sh /cartodb/script/setup_organization.sh
RUN service postgresql start && service redis-server start && \
	bash -l -c "cd /cartodb && bash script/create_dev_user || bash script/create_dev_user && bash script/setup_organization.sh" && \
	service postgresql stop && service redis-server stop


EXPOSE 3000 8080 8181

ENV GDAL_DATA /usr/share/gdal/2.1

ADD ./startup.sh /opt/startup.sh

CMD ["/bin/bash", "/opt/startup.sh"]
