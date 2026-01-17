-- conf.lua
-- Love2D configuration file

function love.conf(t)
    t.identity = "PokeLua"           -- Save directory name
    t.version = "11.4"               -- Love2D version
    t.console = false                -- Debug console (Windows only)
    
    t.window.title = "PokeLua"
    t.window.width = 480
    t.window.height = 612            -- 432 game + 180 controls
    t.window.resizable = false
    t.window.vsync = 1               -- Enable vsync to limit FPS and reduce CPU usage
    
    -- Disable unused modules to reduce overhead
    t.modules.joystick = true
    t.modules.physics = false
    t.modules.video = false
end
