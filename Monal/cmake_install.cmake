# Install script for directory: /Users/anurodhp/Desktop/jrtplib-3.9.0/src

# Set the install prefix
IF(NOT DEFINED CMAKE_INSTALL_PREFIX)
  SET(CMAKE_INSTALL_PREFIX "/usr/local")
ENDIF(NOT DEFINED CMAKE_INSTALL_PREFIX)
STRING(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
IF(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  IF(BUILD_TYPE)
    STRING(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  ELSE(BUILD_TYPE)
    SET(CMAKE_INSTALL_CONFIG_NAME "Release")
  ENDIF(BUILD_TYPE)
  MESSAGE(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
ENDIF(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)

# Set the component getting installed.
IF(NOT CMAKE_INSTALL_COMPONENT)
  IF(COMPONENT)
    MESSAGE(STATUS "Install component: \"${COMPONENT}\"")
    SET(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  ELSE(COMPONENT)
    SET(CMAKE_INSTALL_COMPONENT)
  ENDIF(COMPONENT)
ENDIF(NOT CMAKE_INSTALL_COMPONENT)

IF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")
  FILE(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/jrtplib3" TYPE FILE FILES
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpapppacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpbyepacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpcompoundpacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpcompoundpacketbuilder.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcppacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcppacketbuilder.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcprrpacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpscheduler.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpsdesinfo.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpsdespacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpsrpacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtcpunknownpacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpaddress.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpcollisionlist.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpconfig.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpdebug.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpdefines.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtperrors.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtphashtable.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpinternalsourcedata.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpipv4address.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpipv4destination.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpipv6address.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpipv6destination.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpkeyhashtable.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtplibraryversion.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpmemorymanager.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpmemoryobject.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtppacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtppacketbuilder.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtppollthread.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtprandom.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtprandomrand48.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtprandomrands.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtprandomurandom.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtprawpacket.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpsession.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpsessionparams.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpsessionsources.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpsourcedata.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpsources.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpstructs.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtptimeutilities.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtptransmitter.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtptypes_win.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtptypes.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpudpv4transmitter.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpudpv6transmitter.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpbyteaddress.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/rtpexternaltransmitter.h"
    "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/extratransmitters/rtpfaketransmitter.h"
    )
ENDIF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")

IF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")
  IF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.a")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE STATIC_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/Debug/libjrtp.a")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.a" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
      EXECUTE_PROCESS(COMMAND "/usr/bin/ranlib" "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.a")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE STATIC_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/Release/libjrtp.a")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.a" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
      EXECUTE_PROCESS(COMMAND "/usr/bin/ranlib" "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Mm][Ii][Nn][Ss][Ii][Zz][Ee][Rr][Ee][Ll])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.a")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE STATIC_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/MinSizeRel/libjrtp.a")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.a" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
      EXECUTE_PROCESS(COMMAND "/usr/bin/ranlib" "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Rr][Ee][Ll][Ww][Ii][Tt][Hh][Dd][Ee][Bb][Ii][Nn][Ff][Oo])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.a")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE STATIC_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/RelWithDebInfo/libjrtp.a")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.a" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
      EXECUTE_PROCESS(COMMAND "/usr/bin/ranlib" "$ENV{DESTDIR}/usr/local/lib/libjrtp.a")
    ENDIF()
  ENDIF()
ENDIF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")

IF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")
  IF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.dylib")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE SHARED_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/Debug/libjrtp.dylib")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      EXECUTE_PROCESS(COMMAND "/usr/bin/install_name_tool"
        -id "libjrtp.dylib"
        "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      IF(CMAKE_INSTALL_DO_STRIP)
        EXECUTE_PROCESS(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      ENDIF(CMAKE_INSTALL_DO_STRIP)
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.dylib")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE SHARED_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/Release/libjrtp.dylib")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      EXECUTE_PROCESS(COMMAND "/usr/bin/install_name_tool"
        -id "libjrtp.dylib"
        "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      IF(CMAKE_INSTALL_DO_STRIP)
        EXECUTE_PROCESS(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      ENDIF(CMAKE_INSTALL_DO_STRIP)
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Mm][Ii][Nn][Ss][Ii][Zz][Ee][Rr][Ee][Ll])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.dylib")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE SHARED_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/MinSizeRel/libjrtp.dylib")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      EXECUTE_PROCESS(COMMAND "/usr/bin/install_name_tool"
        -id "libjrtp.dylib"
        "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      IF(CMAKE_INSTALL_DO_STRIP)
        EXECUTE_PROCESS(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      ENDIF(CMAKE_INSTALL_DO_STRIP)
    ENDIF()
  ELSEIF("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Rr][Ee][Ll][Ww][Ii][Tt][Hh][Dd][Ee][Bb][Ii][Nn][Ff][Oo])$")
    list(APPEND CPACK_ABSOLUTE_DESTINATION_FILES
     "/usr/local/lib/libjrtp.dylib")
FILE(INSTALL DESTINATION "/usr/local/lib" TYPE SHARED_LIBRARY FILES "/Users/anurodhp/Desktop/jrtplib-3.9.0/src/RelWithDebInfo/libjrtp.dylib")
    IF(EXISTS "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib" AND
       NOT IS_SYMLINK "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      EXECUTE_PROCESS(COMMAND "/usr/bin/install_name_tool"
        -id "libjrtp.dylib"
        "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      IF(CMAKE_INSTALL_DO_STRIP)
        EXECUTE_PROCESS(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/usr/local/lib/libjrtp.dylib")
      ENDIF(CMAKE_INSTALL_DO_STRIP)
    ENDIF()
  ENDIF()
ENDIF(NOT CMAKE_INSTALL_COMPONENT OR "${CMAKE_INSTALL_COMPONENT}" STREQUAL "Unspecified")

