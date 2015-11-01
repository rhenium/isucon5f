if not ngx.var.cookie_user_id then
    ngx.exit(403)
end

local grade = ngx.var.cookie_grade

ngx.print "var AIR_ISU_REFRESH_INTERVAL = "

if grade == "micro" or grade == "small" then
    ngx.print "30000;"
elseif grade == "standard" then
    ngx.print "20000;"
elseif grade == "premium" then
    ngx.print "10000;"
end
