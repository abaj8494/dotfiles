-- LaTeX Snippets
-- TODO: set options for matrix and table snippets (either auto generate or user input)
-- TODO: fix env function; make it for tikz
local postfix = require("luasnip.extras.postfix").postfix
local line_begin = require("luasnip.extras.expand_conditions").line_begin

-- env stuff
local function math()
    -- global p! functions from UltiSnips
    return vim.api.nvim_eval('vimtex#syntax#in_mathzone()') == 1
end

-- test
local function env(name) 
    local is_inside = vim.fn['vimtex#env#is_inside'](name)
    return (is_inside[1] > 0 and is_inside[2] > 0)
end

local function tikz()
    return env("tikzpicture")
end

local function bp()
    return env("itemize") or env("enumerate")
end


-- table of greek symbols 
griss = {
    alpha = "alpha", beta = "beta", delta = "delta", gam = "gamma", eps = "epsilon",
    mu = "mu", lmbd = "lambda", sig = "sigma"
}

-- brackets
brackets = {
    a = {"<", ">"}, b = {"[", "]"}, c = {"{", "}"}, m = {"|", "|"}, p = {"(", ")"}
}

-- LFG tables and matrices work
local tab = function(args, snip)
	local rows = tonumber(snip.captures[1])
    local cols = tonumber(snip.captures[2])
	local nodes = {}
	local ins_indx = 1
	for j = 1, rows do
		table.insert(nodes, r(ins_indx, tostring(j).."x1", i(1)))
		ins_indx = ins_indx+1
		for k = 2, cols do
			table.insert(nodes, t" & ")
			table.insert(nodes, r(ins_indx, tostring(j).."x"..tostring(k), i(1)))
			ins_indx = ins_indx+1
		end
		table.insert(nodes, t{"\\\\", ""})
        if j == 1 then
            table.insert(nodes, t{"\\midrule", ""})
        end
	end
    nodes[#nodes] = t"\\\\"
    return sn(nil, nodes)
end

-- yes this is a ripoff
local mat = function(args, snip)
	local rows = tonumber(snip.captures[2])
    local cols = tonumber(snip.captures[3])
	local nodes = {}
	local ins_indx = 1
	for j = 1, rows do
		table.insert(nodes, r(ins_indx, tostring(j).."x1", i(1)))
		ins_indx = ins_indx+1
		for k = 2, cols do
			table.insert(nodes, t" & ")
			table.insert(nodes, r(ins_indx, tostring(j).."x"..tostring(k), i(1)))
			ins_indx = ins_indx+1
		end
		table.insert(nodes, t{"\\\\", ""})
	end
	-- fix last node.
	nodes[#nodes] = t"\\\\"
	return sn(nil, nodes)
end

-- TODO: itemize/enumerate
--[[ rec_ls = function() ]]
--[[ 	return sn(nil, { ]]
--[[ 		c(1, { ]]
--[[ 			-- important!! Having the sn(...) as the first choice will cause infinite recursion. ]]
--[[ 			t({""}), ]]
--[[ 			-- The same dynamicNode as in the snippet (also note: self reference). ]]
--[[ 			sn(nil, {t({"", "\t\\item "}), i(1), d(2, rec_ls, {})}), ]]
--[[ 		}), ]]
--[[ 	}); ]]
--[[ end ]]
--[[]]

-- snippets go here

local snippets, autosnippets = {}, {}

local letter =
    s({ trig='t_letter', name='construct letter', dscr='template for a letter'},
    fmt([[
        %-----------------------------------------------------------------------------%

        % Letter class
        \documentclass[a4paper, 10pt]{letter}

        \usepackage{hyperref}
        \hypersetup{colorlinks,urlcolor=blue}
        % Name of sender
        \name{<>}

        % Signature of sender
        \signature{<>}

        % Address of sender
        \address
        {
            <> Street,\\
            <>, <>.
        }

        %-----------------------------------------------------------------------------%

        \begin{document}

        % Name and address of receiver
        \begin{letter}
        {
            <>
        }

        % Opening statement
        \opening{<>}

        % Letter body

        <>

        % Closing statement
        \closing{<>}

        \end{letter}
        \end{document}
        %-----------------------------------------------------------------------------%


    ]],
    { i(1, "sender name"), i(2, "sender signature"), i(3, "street"), i(4, "suburb"), i(5, "state"), i(6, "recipient"), i(7, "opening"), i(8, "body"), i(9, "closing")},
    { delimiters='<>' }
    ))

table.insert(snippets, letter)

local invoice =
    s({ trig='t_invoice', name='create invoice', dscr='template to fill out an invoice.'},
    fmt([[ 
    \documentclass{letter}
    \usepackage[utf8]{inputenc}
    \usepackage[colorlinks]{hyperref}
    \usepackage[left=1in,top=1in,right=1in,bottom=1in]{geometry} % Document margins
    \usepackage{graphicx}
    \usepackage{tabularx}
    \usepackage{multirow}
    \usepackage{ragged2e}
    \usepackage{hhline}
    \usepackage{array}

    \hypersetup{
        urlcolor=blue
    }

    \newcolumntype{R}[1]{!{\raggedleft\let\newline\\\\arraybackslash\hspace{0pt}}m{#1}}

    \begin{document}
        
    \thispagestyle{empty}

    % Header, for company, invoice info
    \begin{tabularx}{\textwidth}{l X l}
        \multirow{5}{*} & \textbf{Private Tutoring} & \hskip12pt\multirow{5}{*}{\begin{tabular}{r}\footnotesize\bf INVOICE \\[-0.8ex] \footnotesize \MakeUppercase{<>} \\[-0.4ex] \footnotesize\bf ISSUE DATE \\[-0.8ex] \footnotesize \MakeUppercase{\today} \\[-0.4ex] \footnotesize\bf DUE DATE\\[-0.8ex] \footnotesize \MakeUppercase{<>} \end{tabular}}\hspace{-6pt} \\
       & Aayush Bajaj & \\
       & \hrulefill \\
       & Email: j@abaj.io & \\
       & Ph:  0481 910 408 & \\
       & ABN: 64257676141
    \end{tabularx} 

    \vspace{1 cm}

    BILL TO

    % Recipient name
    \Large\textbf{<>}\normalsize

    % Table of fees
    \begin{tabularx}{\linewidth}{l X X X c}
        \hline
        & & & &\\[0.25ex]
        \centering{\bf{Service}} & \centering{\bf{Rate}} & \centering{\bf{Quantity}} & \centering{\bf{Discount}} & \bf Payment due\\[2.5ex]\hline
        & & & &\\
        <> & \centering\$<>/hr & \centering <> & \centering -\$<> & \$<>\\[2.5ex]\hline
        & & & &\\
        & & & \bf Total & \$<>\\[2.5ex]\hhline{~~~--}
        & & & & \\
        & & & \bf Received & \$<>\\[2.5ex]\hhline{~~~--}
        & & & & \\
        & & & \bf Balance due & \$<>\\[2.5ex]\hhline{~~~==}
    \end{tabularx}

    \vspace{1 cm}

    \Large\textbf{Payment instructions}\normalsize

    \vspace{0.1 cm}

    \textbf{Account Transfer}\\
    BSB: 633-123\\
    Account Number: 174201004

    \textbf{Pay-ID}\\
    0481 910 408

    \end{document}
    ]],
    { i(1, "period"), i(2, "due date"), i(3, "recipient"), i(4, "service"), i(5, "hourly rate"), i(6, "quantity"), i(7, "discount"), i(8, "due"), i(9, "total"), i(10, "received"), i(11, "total due") },
    { delimiters='<>' }
    ))

table.insert(snippets, invoice)

return snippets, autosnippets
