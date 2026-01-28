// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from SimRa Berlin pothole detection training data
// Model: RandomForestClassifier

/// Pothole detection model using Random Forest
/// Features: ['z_mean', 'z_std', 'z_min', 'z_max', 'z_range', 'x_mean', 'x_std', 'x_range', 'y_mean', 'y_std', 'y_range']
class PotholeDetectionModel {
  
  /// Predict if the sensor window indicates a pothole
  /// Returns probability of pothole (0.0 to 1.0)
  static double predictProbability(List<double> features) {
    // features order: ['z_mean', 'z_std', 'z_min', 'z_max', 'z_range', 'x_mean', 'x_std', 'x_range', 'y_mean', 'y_std', 'y_range']
    assert(features.length == 11, 
        'Expected 11 features, got ${features.length}');
    
    final scores = _predictPothole(features);
    // scores[1] is the pothole probability
    return scores[1].clamp(0.0, 1.0);
  }
  
  /// Returns true if pothole is detected (probability > 0.5)
  static bool isPothole(List<double> features) {
    return predictProbability(features) > 0.5;
  }
  
  /// Feature names in order
  static const List<String> featureNames = ['z_mean', 'z_std', 'z_min', 'z_max', 'z_range', 'x_mean', 'x_std', 'x_range', 'y_mean', 'y_std', 'y_range'];
  
static List<double> _predictPothole(List<double> input) {
    List<double> var0;
    if (input[6] <= 0.0300632081925869) {
        if (input[5] <= -5.207731604576111) {
            var0 = [0.0, 1.0];
        } else {
            if (input[1] <= 0.021395104005932808) {
                var0 = [1.0, 0.0];
            } else {
                if (input[3] <= 2.5992541909217834) {
                    var0 = [0.0, 1.0];
                } else {
                    var0 = [0.6666666666666666, 0.3333333333333333];
                }
            }
        }
    } else {
        if (input[1] <= 0.4314117282629013) {
            if (input[3] <= 8.569321155548096) {
                var0 = [0.0, 1.0];
            } else {
                var0 = [1.0, 0.0];
            }
        } else {
            if (input[3] <= 10.236760139465332) {
                if (input[2] <= 5.197471618652344) {
                    var0 = [0.0, 1.0];
                } else {
                    var0 = [0.2, 0.8];
                }
            } else {
                if (input[3] <= 10.56431245803833) {
                    var0 = [0.75, 0.25];
                } else {
                    var0 = [0.0, 1.0];
                }
            }
        }
    }
    List<double> var1;
    if (input[7] <= 0.10536504909396172) {
        if (input[3] <= 6.513845920562744) {
            var1 = [0.0, 1.0];
        } else {
            var1 = [1.0, 0.0];
        }
    } else {
        if (input[4] <= 1.733619213104248) {
            if (input[2] <= 5.806747555732727) {
                var1 = [0.0, 1.0];
            } else {
                var1 = [1.0, 0.0];
            }
        } else {
            if (input[7] <= 3.7438924312591553) {
                if (input[2] <= 6.454448699951172) {
                    var1 = [0.0, 1.0];
                } else {
                    var1 = [1.0, 0.0];
                }
            } else {
                var1 = [0.0, 1.0];
            }
        }
    }
    List<double> var2;
    if (input[3] <= 9.783095359802246) {
        if (input[2] <= 6.454448699951172) {
            var2 = [0.0, 1.0];
        } else {
            var2 = [1.0, 0.0];
        }
    } else {
        if (input[4] <= 3.685362219810486) {
            var2 = [1.0, 0.0];
        } else {
            var2 = [0.0, 1.0];
        }
    }
    List<double> var3;
    if (input[2] <= 6.377325534820557) {
        var3 = [0.0, 1.0];
    } else {
        var3 = [1.0, 0.0];
    }
    List<double> var4;
    if (input[0] <= 7.8118884563446045) {
        var4 = [0.0, 1.0];
    } else {
        if (input[6] <= 0.8751955926418304) {
            var4 = [1.0, 0.0];
        } else {
            var4 = [0.0, 1.0];
        }
    }
    List<double> var5;
    if (input[2] <= 6.454448699951172) {
        var5 = [0.0, 1.0];
    } else {
        var5 = [1.0, 0.0];
    }
    List<double> var6;
    if (input[2] <= 6.454448699951172) {
        var6 = [0.0, 1.0];
    } else {
        var6 = [1.0, 0.0];
    }
    List<double> var7;
    if (input[0] <= 7.811261415481567) {
        var7 = [0.0, 1.0];
    } else {
        if (input[3] <= 10.384063243865967) {
            if (input[6] <= 0.9399834275245667) {
                var7 = [1.0, 0.0];
            } else {
                if (input[8] <= 0.6743389219045639) {
                    var7 = [0.0, 1.0];
                } else {
                    var7 = [0.5, 0.5];
                }
            }
        } else {
            var7 = [0.0, 1.0];
        }
    }
    List<double> var8;
    if (input[10] <= 0.07439550012350082) {
        if (input[5] <= -5.207731604576111) {
            var8 = [0.0, 1.0];
        } else {
            var8 = [1.0, 0.0];
        }
    } else {
        if (input[4] <= 1.97646164894104) {
            if (input[2] <= 6.454448699951172) {
                var8 = [0.0, 1.0];
            } else {
                var8 = [1.0, 0.0];
            }
        } else {
            if (input[1] <= 0.7864237725734711) {
                if (input[10] <= 6.914950609207153) {
                    var8 = [0.0, 1.0];
                } else {
                    var8 = [0.3333333333333333, 0.6666666666666666];
                }
            } else {
                var8 = [0.0, 1.0];
            }
        }
    }
    List<double> var9;
    if (input[4] <= 1.7267199754714966) {
        if (input[3] <= 6.651764392852783) {
            var9 = [0.0, 1.0];
        } else {
            var9 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 9.683246612548828) {
            if (input[2] <= 5.143075942993164) {
                var9 = [0.0, 1.0];
            } else {
                var9 = [0.3333333333333333, 0.6666666666666666];
            }
        } else {
            var9 = [1.0, 0.0];
        }
    }
    List<double> var10;
    if (input[4] <= 1.733619213104248) {
        if (input[8] <= -0.5432289689779282) {
            if (input[3] <= 6.225872278213501) {
                var10 = [0.0, 1.0];
            } else {
                var10 = [1.0, 0.0];
            }
        } else {
            if (input[9] <= 0.0026399329071864486) {
                if (input[3] <= 9.7308931350708) {
                    var10 = [0.5, 0.5];
                } else {
                    var10 = [1.0, 0.0];
                }
            } else {
                if (input[5] <= -0.6539442837238312) {
                    if (input[0] <= 7.071116924285889) {
                        var10 = [0.0, 1.0];
                    } else {
                        var10 = [1.0, 0.0];
                    }
                } else {
                    if (input[3] <= 4.555033624172211) {
                        var10 = [0.0, 1.0];
                    } else {
                        var10 = [1.0, 0.0];
                    }
                }
            }
        }
    } else {
        if (input[0] <= 8.764192581176758) {
            var10 = [0.0, 1.0];
        } else {
            if (input[7] <= 3.0998716354370117) {
                var10 = [1.0, 0.0];
            } else {
                var10 = [0.6666666666666666, 0.3333333333333333];
            }
        }
    }
    List<double> var11;
    if (input[10] <= 0.07439550012350082) {
        if (input[0] <= 6.503280401229858) {
            var11 = [0.0, 1.0];
        } else {
            var11 = [1.0, 0.0];
        }
    } else {
        if (input[4] <= 1.7267199754714966) {
            if (input[9] <= 0.0987984836101532) {
                if (input[3] <= 7.401546001434326) {
                    var11 = [0.0, 1.0];
                } else {
                    var11 = [1.0, 0.0];
                }
            } else {
                if (input[0] <= 6.703206539154053) {
                    var11 = [0.0, 1.0];
                } else {
                    var11 = [1.0, 0.0];
                }
            }
        } else {
            if (input[2] <= 6.391818523406982) {
                var11 = [0.0, 1.0];
            } else {
                var11 = [1.0, 0.0];
            }
        }
    }
    List<double> var12;
    if (input[2] <= 6.391818523406982) {
        var12 = [0.0, 1.0];
    } else {
        var12 = [1.0, 0.0];
    }
    List<double> var13;
    if (input[7] <= 0.10536504909396172) {
        if (input[9] <= 0.002347705769352615) {
            if (input[10] <= 0.00546673103235662) {
                var13 = [0.5, 0.5];
            } else {
                var13 = [1.0, 0.0];
            }
        } else {
            if (input[2] <= 6.49552845954895) {
                var13 = [0.0, 1.0];
            } else {
                var13 = [1.0, 0.0];
            }
        }
    } else {
        if (input[2] <= 6.459424018859863) {
            var13 = [0.0, 1.0];
        } else {
            var13 = [1.0, 0.0];
        }
    }
    List<double> var14;
    if (input[7] <= 0.10536504909396172) {
        if (input[8] <= 0.49018965661525726) {
            if (input[4] <= 0.1194935031235218) {
                var14 = [1.0, 0.0];
            } else {
                var14 = [0.5, 0.5];
            }
        } else {
            if (input[7] <= 0.019557274878025055) {
                var14 = [0.0, 1.0];
            } else {
                var14 = [1.0, 0.0];
            }
        }
    } else {
        if (input[2] <= 6.454448699951172) {
            var14 = [0.0, 1.0];
        } else {
            var14 = [1.0, 0.0];
        }
    }
    List<double> var15;
    if (input[3] <= 9.776618957519531) {
        if (input[2] <= 6.454448699951172) {
            var15 = [0.0, 1.0];
        } else {
            var15 = [1.0, 0.0];
        }
    } else {
        if (input[1] <= 0.8608055114746094) {
            var15 = [1.0, 0.0];
        } else {
            var15 = [0.0, 1.0];
        }
    }
    List<double> var16;
    if (input[4] <= 1.7267199754714966) {
        if (input[0] <= 6.5060648918151855) {
            var16 = [0.0, 1.0];
        } else {
            var16 = [1.0, 0.0];
        }
    } else {
        if (input[3] <= 9.92637825012207) {
            if (input[3] <= 9.601736545562744) {
                var16 = [0.0, 1.0];
            } else {
                if (input[6] <= 0.9399834275245667) {
                    var16 = [0.5, 0.5];
                } else {
                    var16 = [0.0, 1.0];
                }
            }
        } else {
            if (input[6] <= 0.8854853510856628) {
                var16 = [1.0, 0.0];
            } else {
                var16 = [0.0, 1.0];
            }
        }
    }
    List<double> var17;
    if (input[9] <= 0.009387841913849115) {
        if (input[2] <= 6.498857736587524) {
            var17 = [0.0, 1.0];
        } else {
            var17 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 8.273921966552734) {
            var17 = [0.0, 1.0];
        } else {
            if (input[2] <= 6.337422847747803) {
                var17 = [0.0, 1.0];
            } else {
                var17 = [1.0, 0.0];
            }
        }
    }
    List<double> var18;
    if (input[3] <= 9.776618957519531) {
        if (input[9] <= 0.003628827747888863) {
            if (input[0] <= 6.505437850952148) {
                var18 = [0.0, 1.0];
            } else {
                var18 = [1.0, 0.0];
            }
        } else {
            if (input[2] <= 6.454448699951172) {
                var18 = [0.0, 1.0];
            } else {
                var18 = [1.0, 0.0];
            }
        }
    } else {
        if (input[4] <= 3.677752375602722) {
            var18 = [1.0, 0.0];
        } else {
            var18 = [0.0, 1.0];
        }
    }
    List<double> var19;
    if (input[4] <= 0.1649213507771492) {
        if (input[4] <= 0.02262219972908497) {
            if (input[2] <= 7.406101226806641) {
                var19 = [0.0, 1.0];
            } else {
                var19 = [1.0, 0.0];
            }
        } else {
            if (input[8] <= 0.5154461562633514) {
                var19 = [1.0, 0.0];
            } else {
                var19 = [0.875, 0.125];
            }
        }
    } else {
        if (input[0] <= 8.316439151763916) {
            var19 = [0.0, 1.0];
        } else {
            if (input[0] <= 9.6331205368042) {
                if (input[2] <= 6.342398166656494) {
                    var19 = [0.0, 1.0];
                } else {
                    var19 = [1.0, 0.0];
                }
            } else {
                var19 = [1.0, 0.0];
            }
        }
    }
    List<double> var20;
    if (input[2] <= 6.454448699951172) {
        var20 = [0.0, 1.0];
    } else {
        var20 = [1.0, 0.0];
    }
    List<double> var21;
    if (input[2] <= 6.377325534820557) {
        var21 = [0.0, 1.0];
    } else {
        var21 = [1.0, 0.0];
    }
    List<double> var22;
    if (input[0] <= 7.5982985496521) {
        var22 = [0.0, 1.0];
    } else {
        if (input[2] <= 6.345479726791382) {
            var22 = [0.0, 1.0];
        } else {
            var22 = [1.0, 0.0];
        }
    }
    List<double> var23;
    if (input[7] <= 0.10536504909396172) {
        if (input[3] <= 6.513596057891846) {
            var23 = [0.0, 1.0];
        } else {
            var23 = [1.0, 0.0];
        }
    } else {
        if (input[2] <= 6.459424018859863) {
            var23 = [0.0, 1.0];
        } else {
            var23 = [1.0, 0.0];
        }
    }
    List<double> var24;
    if (input[0] <= 7.811261415481567) {
        var24 = [0.0, 1.0];
    } else {
        if (input[4] <= 3.674899697303772) {
            var24 = [1.0, 0.0];
        } else {
            var24 = [0.0, 1.0];
        }
    }
    List<double> var25;
    if (input[2] <= 6.459424018859863) {
        var25 = [0.0, 1.0];
    } else {
        var25 = [1.0, 0.0];
    }
    List<double> var26;
    if (input[7] <= 0.10488623380661011) {
        if (input[3] <= 6.515179395675659) {
            var26 = [0.0, 1.0];
        } else {
            var26 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 8.273921966552734) {
            var26 = [0.0, 1.0];
        } else {
            if (input[6] <= 0.9399834275245667) {
                var26 = [1.0, 0.0];
            } else {
                if (input[5] <= 0.7113707959651947) {
                    var26 = [0.0, 1.0];
                } else {
                    var26 = [0.6666666666666666, 0.3333333333333333];
                }
            }
        }
    }
    List<double> var27;
    if (input[1] <= 0.4309099018573761) {
        if (input[2] <= 6.380493402481079) {
            var27 = [0.0, 1.0];
        } else {
            var27 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 8.03998851776123) {
            var27 = [0.0, 1.0];
        } else {
            if (input[9] <= 2.075809121131897) {
                var27 = [0.0, 1.0];
            } else {
                var27 = [1.0, 0.0];
            }
        }
    }
    List<double> var28;
    if (input[10] <= 0.07439550012350082) {
        if (input[2] <= 6.495431423187256) {
            var28 = [0.0, 1.0];
        } else {
            var28 = [1.0, 0.0];
        }
    } else {
        if (input[4] <= 2.0848158597946167) {
            if (input[3] <= 7.761310338973999) {
                var28 = [0.0, 1.0];
            } else {
                var28 = [1.0, 0.0];
            }
        } else {
            if (input[2] <= 5.031185150146484) {
                var28 = [0.0, 1.0];
            } else {
                var28 = [0.75, 0.25];
            }
        }
    }
    List<double> var29;
    if (input[7] <= 0.10536504909396172) {
        if (input[7] <= 0.008648954797536135) {
            var29 = [0.6666666666666666, 0.3333333333333333];
        } else {
            if (input[0] <= 6.5046374797821045) {
                var29 = [0.0, 1.0];
            } else {
                var29 = [1.0, 0.0];
            }
        }
    } else {
        if (input[2] <= 6.459424018859863) {
            var29 = [0.0, 1.0];
        } else {
            var29 = [1.0, 0.0];
        }
    }
    List<double> var30;
    if (input[2] <= 6.377422571182251) {
        var30 = [0.0, 1.0];
    } else {
        var30 = [1.0, 0.0];
    }
    List<double> var31;
    if (input[7] <= 0.10536504909396172) {
        if (input[2] <= 6.49876070022583) {
            var31 = [0.0, 1.0];
        } else {
            var31 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 8.236568450927734) {
            var31 = [0.0, 1.0];
        } else {
            if (input[6] <= 0.9399834275245667) {
                var31 = [1.0, 0.0];
            } else {
                var31 = [0.0, 1.0];
            }
        }
    }
    List<double> var32;
    if (input[10] <= 0.07439550012350082) {
        if (input[0] <= 7.395681142807007) {
            var32 = [0.0, 1.0];
        } else {
            var32 = [1.0, 0.0];
        }
    } else {
        if (input[3] <= 8.970093727111816) {
            if (input[10] <= 0.4573267996311188) {
                if (input[0] <= 4.165536522865295) {
                    var32 = [0.0, 1.0];
                } else {
                    var32 = [0.5, 0.5];
                }
            } else {
                var32 = [0.0, 1.0];
            }
        } else {
            if (input[4] <= 3.5162047147750854) {
                var32 = [1.0, 0.0];
            } else {
                var32 = [0.0, 1.0];
            }
        }
    }
    List<double> var33;
    if (input[4] <= 0.1649213507771492) {
        if (input[0] <= 6.505437850952148) {
            var33 = [0.0, 1.0];
        } else {
            var33 = [1.0, 0.0];
        }
    } else {
        if (input[2] <= 6.462505578994751) {
            var33 = [0.0, 1.0];
        } else {
            var33 = [1.0, 0.0];
        }
    }
    List<double> var34;
    if (input[1] <= 0.4140182435512543) {
        if (input[4] <= 0.16849200427532196) {
            if (input[2] <= 6.49552845954895) {
                var34 = [0.0, 1.0];
            } else {
                var34 = [1.0, 0.0];
            }
        } else {
            if (input[5] <= 0.4003373235464096) {
                if (input[5] <= -1.4790074825286865) {
                    var34 = [0.0, 1.0];
                } else {
                    if (input[2] <= 7.960771560668945) {
                        var34 = [0.5, 0.5];
                    } else {
                        var34 = [1.0, 0.0];
                    }
                }
            } else {
                if (input[3] <= 8.512232780456543) {
                    var34 = [0.0, 1.0];
                } else {
                    var34 = [1.0, 0.0];
                }
            }
        }
    } else {
        if (input[4] <= 1.9765413403511047) {
            if (input[9] <= 0.7146295011043549) {
                var34 = [0.0, 1.0];
            } else {
                var34 = [0.6666666666666666, 0.3333333333333333];
            }
        } else {
            var34 = [0.0, 1.0];
        }
    }
    List<double> var35;
    if (input[1] <= 0.4140182435512543) {
        if (input[3] <= 8.192362785339355) {
            if (input[1] <= 0.004393684444949031) {
                var35 = [0.75, 0.25];
            } else {
                var35 = [0.0, 1.0];
            }
        } else {
            var35 = [1.0, 0.0];
        }
    } else {
        if (input[0] <= 8.951091289520264) {
            if (input[8] <= 4.481557846069336) {
                var35 = [0.0, 1.0];
            } else {
                if (input[2] <= 2.2576082944869995) {
                    var35 = [0.0, 1.0];
                } else {
                    var35 = [0.5, 0.5];
                }
            }
        } else {
            if (input[7] <= 5.61036479473114) {
                var35 = [1.0, 0.0];
            } else {
                var35 = [0.0, 1.0];
            }
        }
    }
    List<double> var36;
    if (input[6] <= 0.03191515989601612) {
        if (input[4] <= 0.2072310484945774) {
            if (input[2] <= 6.49552845954895) {
                var36 = [0.0, 1.0];
            } else {
                var36 = [1.0, 0.0];
            }
        } else {
            var36 = [0.25, 0.75];
        }
    } else {
        if (input[2] <= 6.416514873504639) {
            var36 = [0.0, 1.0];
        } else {
            var36 = [1.0, 0.0];
        }
    }
    List<double> var37;
    if (input[2] <= 6.454448699951172) {
        var37 = [0.0, 1.0];
    } else {
        var37 = [1.0, 0.0];
    }
    List<double> var38;
    if (input[4] <= 1.3425114154815674) {
        if (input[4] <= 0.16330625116825104) {
            if (input[2] <= 6.49876070022583) {
                var38 = [0.0, 1.0];
            } else {
                var38 = [1.0, 0.0];
            }
        } else {
            if (input[2] <= 6.424235105514526) {
                var38 = [0.0, 1.0];
            } else {
                var38 = [1.0, 0.0];
            }
        }
    } else {
        if (input[7] <= 2.5576480627059937) {
            if (input[0] <= 7.427691221237183) {
                var38 = [0.0, 1.0];
            } else {
                var38 = [1.0, 0.0];
            }
        } else {
            if (input[1] <= 0.293094739317894) {
                if (input[8] <= -4.9113686084747314) {
                    var38 = [0.0, 1.0];
                } else {
                    var38 = [0.5, 0.5];
                }
            } else {
                var38 = [0.0, 1.0];
            }
        }
    }
    List<double> var39;
    if (input[0] <= 7.8118884563446045) {
        var39 = [0.0, 1.0];
    } else {
        if (input[10] <= 5.215027093887329) {
            var39 = [1.0, 0.0];
        } else {
            if (input[2] <= 6.337422847747803) {
                var39 = [0.0, 1.0];
            } else {
                var39 = [1.0, 0.0];
            }
        }
    }
    List<double> var40;
    if (input[4] <= 0.1649213507771492) {
        if (input[2] <= 6.49876070022583) {
            var40 = [0.0, 1.0];
        } else {
            var40 = [1.0, 0.0];
        }
    } else {
        if (input[2] <= 6.462505578994751) {
            var40 = [0.0, 1.0];
        } else {
            var40 = [1.0, 0.0];
        }
    }
    List<double> var41;
    if (input[2] <= 6.459424018859863) {
        var41 = [0.0, 1.0];
    } else {
        var41 = [1.0, 0.0];
    }
    List<double> var42;
    if (input[0] <= 8.236568450927734) {
        if (input[9] <= 0.0031501182820647955) {
            var42 = [0.2857142857142857, 0.7142857142857143];
        } else {
            var42 = [0.0, 1.0];
        }
    } else {
        if (input[1] <= 0.7472382485866547) {
            var42 = [1.0, 0.0];
        } else {
            var42 = [0.0, 1.0];
        }
    }
    List<double> var43;
    if (input[2] <= 6.377422571182251) {
        var43 = [0.0, 1.0];
    } else {
        var43 = [1.0, 0.0];
    }
    List<double> var44;
    if (input[2] <= 6.370410203933716) {
        var44 = [0.0, 1.0];
    } else {
        var44 = [1.0, 0.0];
    }
    List<double> var45;
    if (input[7] <= 0.35941174626350403) {
        if (input[3] <= 6.513845920562744) {
            var45 = [0.0, 1.0];
        } else {
            var45 = [1.0, 0.0];
        }
    } else {
        if (input[2] <= 6.459424018859863) {
            var45 = [0.0, 1.0];
        } else {
            var45 = [1.0, 0.0];
        }
    }
    List<double> var46;
    if (input[6] <= 0.02724671084433794) {
        if (input[5] <= -5.207731604576111) {
            var46 = [0.0, 1.0];
        } else {
            if (input[2] <= 5.669393062591553) {
                var46 = [0.0, 1.0];
            } else {
                var46 = [1.0, 0.0];
            }
        }
    } else {
        if (input[3] <= 9.397127151489258) {
            if (input[6] <= 0.3451004773378372) {
                if (input[10] <= 2.1105092763900757) {
                    if (input[4] <= 0.3261156976222992) {
                        var46 = [0.0, 1.0];
                    } else {
                        if (input[0] <= 7.347820520401001) {
                            var46 = [0.0, 1.0];
                        } else {
                            var46 = [1.0, 0.0];
                        }
                    }
                } else {
                    var46 = [0.0, 1.0];
                }
            } else {
                var46 = [0.0, 1.0];
            }
        } else {
            if (input[2] <= 6.337422847747803) {
                var46 = [0.0, 1.0];
            } else {
                var46 = [1.0, 0.0];
            }
        }
    }
    List<double> var47;
    if (input[2] <= 6.479145050048828) {
        var47 = [0.0, 1.0];
    } else {
        var47 = [1.0, 0.0];
    }
    List<double> var48;
    if (input[2] <= 6.391818523406982) {
        var48 = [0.0, 1.0];
    } else {
        var48 = [1.0, 0.0];
    }
    List<double> var49;
    if (input[0] <= 7.748046159744263) {
        var49 = [0.0, 1.0];
    } else {
        if (input[4] <= 3.674899697303772) {
            var49 = [1.0, 0.0];
        } else {
            var49 = [0.0, 1.0];
        }
    }
    return _mulVectorNumber(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(_addVectors(var0, var1), var2), var3), var4), var5), var6), var7), var8), var9), var10), var11), var12), var13), var14), var15), var16), var17), var18), var19), var20), var21), var22), var23), var24), var25), var26), var27), var28), var29), var30), var31), var32), var33), var34), var35), var36), var37), var38), var39), var40), var41), var42), var43), var44), var45), var46), var47), var48), var49), 0.02);
}
static List<double> _addVectors(List<double> v1, List<double> v2) {
    List<double> result = List<double>.filled(v1.length, 0.0);
    for (int i = 0; i < v1.length; i++) {
        result[i] = v1[i] + v2[i];
    }
    return result;
}
static List<double> _mulVectorNumber(List<double> v1, double num) {
    List<double> result = List<double>.filled(v1.length, 0.0);
    for (int i = 0; i < v1.length; i++) {
        result[i] = v1[i] * num;
    }
    return result;
}

}
