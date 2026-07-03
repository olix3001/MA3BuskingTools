local utils = {}

function utils.greet()
    Printf("Hello from utils!")
end

function utils.debug_table(data)
    for key, value in pairs(data) do
      if type(value) == "table" then
        Printf("Key: " .. key .. " ; Value type is: " .. type(value))
      else
        Printf("Key: " .. key .. " ; Value type is: " .. type(value) .. " ; Value: " .. value)
      end
    end
end

return utils