module Hapi

export build_regex

using FilePaths
using Dagger
using ClusterManagers

function build_regex(pattern, groups)
    for (g, p) in pairs(groups)
        pattern = replace(pattern, string('{',g,'}')=> "(?<$g>$p)")
    end
    return Regex(pattern)
end

end