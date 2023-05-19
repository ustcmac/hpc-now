#!/bin/bash

# Shanghai HPC-NOW Technologies Co., Ltd
# All rights reserved, Year 2023
# https://www.hpc-now.com
# mailto: info@hpc-now.com 
# This script is used by 'hpcmgr' command to build *OpenFOAM-v2112* to HPC-NOW cluster.

if [ ! -d /hpc_apps ]; then
  echo -e "[ FATAL: ] The root directory /hpc_apps is missing. Installation abort. Exit now."
  exit
fi

URL_ROOT=https://hpc-now-1308065454.cos.ap-guangzhou.myqcloud.com/
URL_PKGS=${URL_ROOT}packages/

source /etc/profile
time_current=`date "+%Y-%m-%d %H:%M:%S"`
logfile=/var/log/hpcmgr_install.log && echo -e "\n# $time_current INSTALLING OpenFOAM-v2112" >> ${logfile}
tmp_log=/tmp/hpcmgr_install.log
APP_ROOT=/hpc_apps
NUM_PROCESSORS=`cat /proc/cpuinfo| grep "processor"| wc -l`

ls /hpc_apps/OpenFOAM/OpenFOAM-v2112/platforms/linux*/bin/*Foam >> /dev/null 2>&1
if [ $? -eq 0 ]; then
  foam2112check=`ls /hpc_apps/OpenFOAM/OpenFOAM-v2112/platforms/linux*/bin/*Foam | wc -l` 
  if [ $foam2112check -gt $((80)) ]; then
    cat /etc/profile | grep of2112 >> /dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo -e "alias of2112='source $APP_ROOT/OpenFOAM/of2112.sh'" >> /etc/profile
    fi
    echo -e "[ -INFO- ] It seems $foam2112check Openfoam2112 binaries are in place."
    echo -e "[ -INFO- ] If you REALLY want to rebuild, please move the previous binaries to other folders and retry. Exit now." 
    exit
  fi
fi
echo -e "[ -INFO- ] Cleaning up processes..."
ps -aux | grep OpenFOAM-v2112/wmake | cut -c 9-15 | xargs kill -9 >> /dev/null 2>&1
if [[ -n $1 && $1 = 'rebuild' ]]; then
  echo -e "[ -WARN- ] The previously OpenFOAM and Third-party folder will be removed and re-created."
  rm -rf $APP_ROOT/OpenFOAM/OpenFOAM-v2112
  rm -rf $APP_ROOT/OpenFOAM/ThirdParty-v2112 
fi
yum list installed -q | grep zlib-devel >> /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "[ -INFO- ] OpenFOAM-v2112 needs zlib-devel. Installing now ..."
  yum -y install zlib-devel -q
fi

CENTOS_VER=`cat /etc/redhat-release | awk '{print $4}' | awk -F"." '{print $1}'`

yum list installed -q | grep "cmake\." | grep "3\.">> /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "[ -INFO- ] OpenFOAM-v2112 needs cmake3. Installing now ..."
  if [ $CENTOS_VER -eq 7 ]; then
    yum -y install cmake3 -q >> $tmp_log 2>&1
    rm -rf /bin/cmake
    ln -s /bin/cmake3 /bin/cmake
  else
    yum -y install cmake -q >> $tmp_log 2>&1
  fi
fi

yum install gmp-devel mpfr-devel -y >> $tmp_log 2>&1

yum list installed -q | grep flex >> /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "[ -INFO- ] OpenFOAM-v2112 needs flex. Installing now ..."
  yum -y install flex -q >> $tmp_log 2>&1
fi

#source /opt/environment-modules/init/bash
hpcmgr install envmod >> $tmp_log 2>&1
module ava -t | grep gcc-12.1.0 >> /dev/null 2>&1
if [ $? -eq 0 ]; then
  module load gcc-12.1.0
  gcc_v=gcc-12.1.0
  gcc_vnum=12
  systemgcc='false'
  echo -e "[ -INFO- ] OpenFOAM will be built with GNU C Compiler: $gcc_v"
else
  module ava -t | grep gcc-8.2.0 >> /dev/null 2>&1
  if [ $? -eq 0 ]; then
    module load gcc-8.2.0
    gcc_v=gcc-8.2.0
    gcc_vnum=8
    systemgcc='false'
    echo -e "[ -INFO- ] OpenFOAM will be built with GNU C Compiler: $gcc_v"
  else
    gcc_v=`gcc --version | head -n1`
    gcc_vnum=`echo $gcc_v | awk '{print $3}' | awk -F"." '{print $1}'`
    systemgcc='true'
    echo -e "[ -INFO- ] OpenFOAM will be built with GNU C Compiler: $gcc_v"
    if [ $gcc_vnum -lt 8 ]; then
      echo -e "[ -WARN- ] Your gcc version is too old to compile OpenFOAM. Will start installing gcc-12.1.0 which may take long time."
      echo -e "[ -WARN- ] You can press keyboard 'Ctrl C' to stop current building process."
      echo -ne "[ -WAIT- ] |--> "
      for i in $( seq 1 10)
      do
	      sleep 1
        echo -ne "$((11-i))--> "
      done
      echo -e "|\n[ -INFO- ] Building gcc-12.1.0 now ..."
      hpcmgr install gcc12 >> ${tmp_log}
      gcc_v=gcc-12.1.0
      gcc_vnum=12
      systemgcc='false'
      module load gcc-12.2.0
    fi
  fi
fi
module ava -t | grep mpich >> /dev/null 2>&1
if [ $? -eq 0 ]; then
  mpi_version=`module ava -t | grep mpich | tail -n1 | awk '{print $1}'`
  module load $mpi_version
  echo -e "[ -INFO- ] OpenFOAM will be built with $mpi_version."
else
  module ava -t | grep ompi >> /dev/null 2>&1
  if [ $? -eq 0 ]; then
    mpi_version=`module ava -t | grep ompi | tail -n1 | awk '{print $1}'`
    module load $mpi_version
    echo -e "[ -INFO- ] OpenFOAM will be built with $mpi_version."
  else
    echo -e "[ -INFO- ] No MPI version found, installing MPICH-4.0.2 now..."
    hpcmgr install mpich4 >> ${tmp_log}.mpich4
    if [ $? -ne 0 ]; then
      echo -e "[ FATAL: ] Failed to install MPICH-4.0.2. Installation abort. Please check the log file for details. Exit now."
      exit
    else
      echo -e "[ -INFO- ] MPICH-4.0.2 has been successfully built."
      mpi_version=mpich-4.0.2
      module purge
      module load $mpi_version
    fi
  fi
fi

echo -e "[ START: ] $time_current Building OpenFOAM-v2112 now ... "
echo -e "[ START: ] $time_current Building OpenFOAM-v2112 now ... " >> $logfile
mkdir -p $APP_ROOT/OpenFOAM
echo -e "[ STEP 1 ] $time_current Downloading & extracting source packages ..."
echo -e "[ STEP 1 ] $time_current Downloading & extracting source packages ..." >> $logfile
if [ ! -f $APP_ROOT/OpenFOAM/OpenFOAM-v2112.tgz ]; then
  wget ${URL_PKGS}OpenFOAM-v2112.tgz -q -O $APP_ROOT/OpenFOAM/OpenFOAM-v2112.tgz
fi  
if [ ! -f $APP_ROOT/OpenFOAM/ThirdParty-v2112.tgz ]; then
  wget ${URL_PKGS}ThirdParty-v2112.tgz -q -O $APP_ROOT/OpenFOAM/ThirdParty-v2112.tgz
fi
if [ ! -d $APP_ROOT/OpenFOAM/OpenFOAM-v2112 ]; then
  cd $APP_ROOT/OpenFOAM && tar zvxf OpenFOAM-v2112.tgz >> $tmp_log 2>&1
fi
if [ ! -d $APP_ROOT/OpenFOAM/ThirdParty-v2112 ]; then
  cd $APP_ROOT/OpenFOAM && tar zvxf ThirdParty-v2112.tgz >> $tmp_log 2>&1
fi
if [ ! -f $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources/ADIOS2-2.6.0.zip ]; then
  wget ${URL_PKGS}ADIOS2-2.6.0.zip -O $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources/ADIOS2-2.6.0.zip >> $tmp_log 2>&1
fi
#cd $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources && rm -rf ADIOS2-2.6.0 && unzip ADIOS2-2.6.0.zip >> $tmp_log 2>&1
if [ ! -f $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources/metis-5.1.0.tar.gz ]; then
  wget ${URL_PKGS}metis-5.1.0.tar.gz -O $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources/metis-5.1.0.tar.gz -q
fi
#cd $APP_ROOT/OpenFOAM/ThirdParty-v2112/sources && rm -rf metis-5.1.0 && tar zvxf metis-5.1.0.tar.gz >> $tmp_log 2>&1
echo -e "[ -INFO- ] Removing the tarballs are not recommended. If you want to rebuild of2112, please remove the folder OpenFOAM-v2112 & ThirdParty-v2112."
time_current=`date "+%Y-%m-%d %H:%M:%S"`
echo -e "[ STEP 2 ] $time_current Removing previously-built binaries ..."
echo -e "[ STEP 2 ] $time_current Removing previously-built binaries ..." >> $logfile
#rm -rf $APP_ROOT/OpenFOAM/OpenFOAM-v2112/platforms/*
#rm -rf $APP_ROOT/OpenFOAM/ThirdParty-v2112/platforms/* 
time_current=`date "+%Y-%m-%d %H:%M:%S"`
echo -e "[ STEP 3 ] $time_current Compiling started ..."
if [ ! -f  $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/settings-orig ]; then
  cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/settings $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/settings-orig
else
  /bin/cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/settings-orig $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/settings 
fi
if [ ! -f $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c-orig ]; then
  cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c-orig
else
  /bin/cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c-orig $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c
fi
if [ ! -f $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++-orig ]; then
  cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++ $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++-orig
else
  /bin/cp  $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++-orig $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++
fi
if [ ! -f $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc-orig ]; then
  cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc-orig
else
  /bin/cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc-orig $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc
fi
if [ $gcc_vnum -gt 10 ]; then
  cat /proc/cpuinfo | grep "model name" | grep "AMD EPYC"  >> /dev/null 2>&1
  if [ $? -eq 0 ]; then
    cpu_model=`cat /proc/cpuinfo | grep "model name" | grep "AMD EPYC" | head -n1 | awk '{print $6}'`
    cpu_gen=${cpu_model: -1}
    if [ $cpu_gen = '3' ]; then
      sed -i 's/-fPIC/-fPIC -march=znver3/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c
      sed -i 's/-fPIC/-fPIC -march=znver3/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++
    elif [ $cpu_gen = '2' ]; then
      sed -i 's/-fPIC/-fPIC -march=znver2/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c
      sed -i 's/-fPIC/-fPIC -march=znver2/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/wmake/rules/linux64Gcc/c++
    fi
  fi
fi    
sed -i 's/export WM_MPLIB=SYSTEMOPENMPI/export WM_MPLIB=SYSTEMMPI/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc
export MPI_ROOT=/hpc_apps/$mpi_version
echo "$mpi_version" | grep ompi >> /dev/null 2>&1
if [ $? -eq 0 ]; then
  export MPI_ARCH_FLAGS="-DOMPI_SKIP_MPICXX"
else
  export MPI_ARCH_FLAGS="-DMPICH_SKIP_MPICXX"
fi
export MPI_ARCH_INC="-I/hpc_apps/$mpi_version/include" 
export MPI_ARCH_LIBS="-L/hpc_apps/$mpi_version/lib -lmpi"
#echo -e $MPI_ROOT $MPI_ARCH_FLAGS $MPI_ARCH_INC $MPI_ARCH_LIBS
#/bin/cp $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/adios2 $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/adios2-orig
#sed -i 's/adios2_version=ADIOS2-2.6.0/adios2_version=ADIOS2-2.7.1/g' $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/config.sh/adios2
source $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc
echo -e "[ -INFO- ] Building OpenFOAM in progress ... It takes really long time (for example, 2.5 hours with 8 vCPUs).\n[ -INFO- ] Please check the log files: Build_OF.log."
export FOAM_EXTRA_LDFLAGS="-L/hpc_apps/OpenFOAM/ThirdParty-v2112/platforms/linux64Gcc/fftw-3.3.10/lib -lfftw3"
time_current=`date "+%Y-%m-%d %H:%M:%S"`
echo -e "[ STEP 3 ] $time_current Started compiling source codes ..." >> $logfile
#module load $mpi_version
PATH=$APP_ROOT/$mpi_version/bin:$PATH LD_LIBRARY_PATH=$APP_ROOT/$mpi_version/lib:$LD_LIBRARY_PATH
$APP_ROOT/OpenFOAM/ThirdParty-v2112/Allclean -build > $APP_ROOT/OpenFOAM/Build_OF.log 2>&1
$APP_ROOT/OpenFOAM/OpenFOAM-v2112/Allwmake -j$NUM_PROCESSORS >> $APP_ROOT/OpenFOAM/Build_OF.log 2>&1
if [ $? -ne 0 ]; then
  echo -e "[ FATAL: ] Building OpenFOAM-v2112 failed. Please check the Build_OF.log and retry later. Exit now."
  exit
fi
if [ $systemgcc = 'true' ]; then
  echo -e "#! /bin/bash\nmodule purge\nexport MPI_ROOT=/hpc_apps/$mpi_version\nexport MPI_ARCH_FLAGS=\"-DMPICH_SKIP_MPICXX\"\nexport MPI_ARCH_INC=\"-I\$MPI_ROOT/include\"\nexport MPI_ARCH_LIBS=\"-L\$MPI_ROOT/lib -lmpi\"\nmodule load $mpi_version\nsource $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc\necho \"Openfoam2112 with $mpi_version and system gcc: $gcc_v is ready for running.\"" > $APP_ROOT/OpenFOAM/of2112.sh
else
  echo -e "#! /bin/bash\nmodule purge\nexport MPI_ROOT=/hpc_apps/$mpi_version\nexport MPI_ARCH_FLAGS=\"-DMPICH_SKIP_MPICXX\"\nexport MPI_ARCH_INC=\"-I\$MPI_ROOT/include\"\nexport MPI_ARCH_LIBS=\"-L\$MPI_ROOT/lib -lmpi\"\nmodule load $mpi_version\nmodule load $gcc_v\nsource $APP_ROOT/OpenFOAM/OpenFOAM-v2112/etc/bashrc\necho \"Openfoam2112 with $mpi_version and $gcc_v is ready for running.\"" > $APP_ROOT/OpenFOAM/of2112.sh
fi

cat /etc/profile | grep of2112 >> /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "alias of2112='source $APP_ROOT/OpenFOAM/of2112.sh'" >> /etc/profile
fi
echo -e "[ -DONE- ] Congratulations! OpenFOAM-v2112 with $mpi_version and $gcc_v has been built."
time_current=`date "+%Y-%m-%d %H:%M:%S"`
echo -e "[ -DONE- ] $time_current Congratulations! OpenFOAM-v2112 with $mpi_version and $gcc_v has been built." >> $logfile