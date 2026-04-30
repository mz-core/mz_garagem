MZGaragemGarages = {

  public_airport = {
    id = 'public_airport',
    label = 'Public Airport',
    kind = 'public',
    zone = {
      coords = vec3(-993.20, -2950.96, 13.96),
      radius = 3.0
    },
    spawn_points = {
      vec4(-990.02, -2999.90, 14.48, 59.45)
    },
    blip = {
      enabled = true,
      sprite = 357,
      color = 3,
      scale = 0.6,
      label = 'Public Airport'
    },
    interact = {
      icon = {
        textureDict = 'mod_icon',
        textureName = 'car_service_icon'
      }
    },
    store = {
      enabled = true,
      coords = vec3(-990.02, -2999.90, 14.48),
      radius = 3.5,
      interact = {
        enabled = true,
        drawDistance = 18.0,
        interactDistance = 10.5,
        marker = {
          enabled = true,
          type = 1,
          size = vec3(3.5, 3.5, 0.18),
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = {
          enabled = false
        }
      }
    },
    filters = {
      categories = { 'plane' }
    },
    rules = {
      strict_garage = false,
      shared_pool = true,
      allow_impounded = true
    }
  },
  
  pillbox_public = {
    id = 'pillbox_public',
    label = 'Pillbox Garage',
    kind = 'public',
    zone = {
      coords = vec3(215.8, -810.1, 30.7),
      radius = 3.0
    },
    spawn_points = {
      vec4(231.0, -801.3, 30.6, 157.0),
      vec4(235.2, -803.8, 30.5, 157.0),
      vec4(239.6, -806.5, 30.4, 157.0),
      vec4(244.0, -809.1, 30.3, 157.0),
      vec4(248.3, -811.8, 30.2, 157.0)
    },
    blip = {
      enabled = true,
      sprite = 357,
      color = 3,
      scale = 0.6,
      label = 'Public Garage'
    },
    interact = {
      icon = {
        textureDict = 'mod_icon',
        textureName = 'car_service_icon'
      }
    },
    store = {
      enabled = true,
      coords = vec3(209.21, -806.82, 29.90),
      radius = 3.5,
      interact = {
        enabled = true,
        drawDistance = 18.0,
        interactDistance = 4.0,
        marker = {
          enabled = true,
          type = 1,
          size = vec3(3.5, 3.5, 0.18),
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = {
          enabled = false
        }
      }
    },
    filters = {
      categories = { 'car' }
    },
    rules = {
      strict_garage = true,
      shared_pool = false,
      allow_impounded = true
    }
  },

  police_org = {
    id = 'police_org',
    label = 'Police Garage',
    kind = 'org',
    org_code = 'police',
    zone = {
      coords = vec3(454.7, -1017.4, 28.4),
      radius = 3.0
    },
    spawn_points = {
      vec4(438.4, -1018.3, 27.7, 90.0),
      vec4(442.5, -1020.4, 28.0, 90.0)
    },
    blip = {
      enabled = false,
      sprite = 357,
      color = 38,
      scale = 0.6,
      label = 'Police Garage'
    },
    store = {
      enabled = true,
      coords = vec3(449.5, -1018.5, 28.4),
      radius = 3.5,
      interact = {
        enabled = true,
        drawDistance = 18.0,
        interactDistance = 4.0,
        marker = {
          enabled = true,
          type = 1,
          size = vec3(3.5, 3.5, 0.18),
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = {
          enabled = false
        }
      }
    },
    filters = {
      categories = { 'car' }
    },
    access = {
      require_membership = true,
      require_duty = false,
      min_grade_level = 0,
      primary_only = false,
      required_org_permissions = {}
    },
    rules = {
      strict_garage = true,
      shared_pool = false,
      allow_impounded = false
    }
  },

  police_service = {
    id = 'police_service',
    label = 'Police Service Fleet',
    kind = 'service',
    org_code = 'police',
    fleet_id = 'police_patrol',
    zone = {
      coords = vec3(462.9, -1019.4, 28.1),
      radius = 3.0
    },
    spawn_points = {
      vec4(446.2, -1025.8, 28.2, 6.0),
      vec4(442.4, -1025.6, 28.3, 6.0)
    },
    blip = {
      enabled = false,
      sprite = 357,
      color = 38,
      scale = 0.6,
      label = 'Police Service Fleet'
    },
    store = {
      enabled = true,
      coords = vec3(458.4, -1024.0, 28.2),
      radius = 3.5,
      interact = {
        enabled = true,
        drawDistance = 18.0,
        interactDistance = 4.0,
        marker = {
          enabled = true,
          type = 1,
          size = vec3(3.5, 3.5, 0.18),
          color = { r = 80, g = 210, b = 255, a = 70 },
          bobUpAndDown = false,
          rotate = false,
          faceCamera = false
        },
        text = {
          enabled = true,
          label = '[E] Guardar veiculo',
          offsetZ = 0.45
        },
        blip = {
          enabled = false
        }
      }
    },
    filters = {
      categories = { 'car' }
    },
    access = {
      require_membership = true,
      require_duty = true,
      min_grade_level = 0,
      primary_only = false,
      required_org_permissions = {}
    },
    service = {
      limit_one_active = true
    }
  }
}
