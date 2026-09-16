const encoded = "yb~iB}dt}Mz@f@jDpAl@`@Pc@lAgBdA}AtA_B\\}@Lk@Ho@?kAC_BDw@d@uBnAgEPiAj@iBr@uBR_@Xc@Z]lAw@x@q@NUn@}A`AuCxAeEjAwCb@kAr@aCTg@XYlA}@dA{@z@o@LKVOZSPKHMNUn@kAzBaElAgBjC}DdAgBb@{@f@uAbA_DP[`AsAXa@LCP?VBh@DXC`@WVq@^yAhAqDd@oBX{@pDcMf@cBB[?Mc@FkBN}ARu@BAQGyCIoAMwFGcCa@_LGsBEsClB_AxEaCf@I|CVdALJ{@ZeCzA_MR}@L_AFWpA{@n@YpC{@FAMi@KeBCmDFqEBeE@{EFgANk@`E}G^o@^g@|A}Ab@_@XQt@QbAO`AO`AKTIZWz@aBbDmGv@yAZk@lCkEn@cAjAuB`@}@J_@Jk@Rs@bBqEd@kAb@sAdBwENa@@QAGEKSMeAi@AAEGQGaC{@eC_Aw@SoBk@wAYyEw@_H{@o@KFYbDh@jFn@`CT|@RtBj@~HnCdDjATJDOJWBUGc@ISgAoCyDcIiCkFa@gAeCyH{@iCsAeD{AgDWc@_C}CgAsAo@_Ai@eAk@yAiAgDUu@a@eB[uA[gBE]@MEQ]cC]cBq@uDMw@CoAA[?gABqEFsI@{COuAWcBS_Au@aDo@aC[eAe@eAu@}AoAmB[eAk@sCGo@IsDk@qEW_BIw@GmDAq@GqAMi@Wi@Qe@Uo@_@w@o@y@a@k@M[]kAe@aAo@mAw@gBqAsCUk@m@}BOsACeABoAXkB|@kDdAsDh@sAh@mB`@iBPkAb@kAR]P]mBiAcAk@aB}@qEyCgAm@aAa@QKDKRi@n@_ChB{GNI`AUr@KZ?x@Hn@JrBn@zBr@j@Z~A`@X@j@ItAa@bDaA`@OpAUbDa@xCYdBM";

// Strip all backslashes (both single and double if any)
const stripped = encoded.replace(/\\/g, '');

function decodePolyline(encoded) {
  let poly = [];
  let index = 0, len = encoded.length;
  let lat = 0, lng = 0;

  while (index < len) {
    let b, shift = 0, result = 0;
    do {
      if (index >= len) break;
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      if (index >= len) break;
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    poly.push({ lat: lat / 1E5, lng: lng / 1E5 });
  }
  return poly;
}

const decoded = decodePolyline(stripped);
console.log('Stripped Decoded count:', decoded.length);
console.log('Stripped First 5:', decoded.slice(0, 5));
console.log('Stripped Last 5:', decoded.slice(-5));
