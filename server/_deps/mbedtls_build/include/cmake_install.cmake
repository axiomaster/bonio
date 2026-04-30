# Install script for directory: D:/projects/bonio/server/third_party/mbedtls/include

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "C:/Program Files (x86)/hiclaw")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/mbedtls" TYPE FILE PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ FILES
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/aes.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/aria.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/asn1.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/asn1write.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/base64.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/bignum.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/block_cipher.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/build_info.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/camellia.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ccm.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/chacha20.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/chachapoly.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/check_config.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/cipher.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/cmac.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/compat-2.x.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_legacy_crypto.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_legacy_from_psa.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_psa_from_legacy.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_psa_superset_legacy.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_ssl.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_adjust_x509.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/config_psa.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/constant_time.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ctr_drbg.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/debug.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/des.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/dhm.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ecdh.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ecdsa.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ecjpake.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ecp.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/entropy.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/error.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/gcm.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/hkdf.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/hmac_drbg.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/lms.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/mbedtls_config.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/md.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/md5.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/memory_buffer_alloc.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/net_sockets.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/nist_kw.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/oid.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/pem.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/pk.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/pkcs12.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/pkcs5.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/pkcs7.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/platform.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/platform_time.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/platform_util.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/poly1305.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/private_access.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/psa_util.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ripemd160.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/rsa.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/sha1.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/sha256.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/sha3.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/sha512.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ssl.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ssl_cache.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ssl_ciphersuites.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ssl_cookie.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/ssl_ticket.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/threading.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/timing.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/version.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/x509.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/x509_crl.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/x509_crt.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/mbedtls/x509_csr.h"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/psa" TYPE FILE PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ FILES
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/build_info.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_adjust_auto_enabled.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_adjust_config_dependencies.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_adjust_config_key_pair_types.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_adjust_config_synonyms.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_builtin_composites.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_builtin_key_derivation.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_builtin_primitives.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_compat.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_config.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_driver_common.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_driver_contexts_composites.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_driver_contexts_key_derivation.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_driver_contexts_primitives.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_extra.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_legacy.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_platform.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_se_driver.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_sizes.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_struct.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_types.h"
    "D:/projects/bonio/server/third_party/mbedtls/include/psa/crypto_values.h"
    )
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "D:/projects/bonio/server/_deps/mbedtls_build/include/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
