# Info
I use a HarmonyOS phone in China, so I ported the android platform app to HarmonyOS platform.

# Build Config 

- Use IDE ```DevEco Studio``` open the project
- Apply the debug key
- config the sign key by ```DevEco Studio``` or directly in the build-profile.json5
- then build the project by IDE or CLI

```json
    "signingConfigs": [
      {
        "name": "default",
        "type": "HarmonyOS",
        "material": {
          "certpath": "/path/to/xxx.cer ",
          "keyAlias": "debugKey",
          "keyPassword": "keyPassword",
          "profile": "/path/to/xxx.p7b",
          "signAlg": "SHA256withECDSA",
          "storeFile": "/path/to/xxx.p12",
          "storePassword": "storePassword"
        }
      }
    ]
```
