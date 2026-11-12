---------------------------------------------------------------------------------------
-- ExplorationOverlays - zone "revealed" overlay region data
-- Copyright 2007-2012 Carbon Based Creations, LLC
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- Carbonite - Addon for World of Warcraft(tm)
-- Copyright 2007-2012 Carbon Based Creations, LLC
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
---------------------------------------------------------------------------------------

-- Alchemy GPS port note (build-order step 21, CORRECTED same day):
-- this is NOT the file originally ported here. The first pass copied
-- Carbonite/Data/camelot/MapData/ExplorationOverlays.lua (842 lines,
-- named-region keys like ["hilsbrad"]={["tarrenmill"]=...}), matching
-- its MapWorldInfo[x].Overlay field (e.g. "hillsbrad_c60") against
-- NOTHING - that file's keys never had the "_c60" suffix at all, so
-- every single lookup failed silently, every tick, for every zone.
--
-- Live-tested: reported "100% unexplored" at every zoom level that
-- should show revealed zone art. Added temporary /gps dbgoverlay
-- logging, which confirmed `self.ZoneOverlays["hillsbrad_c60"]` was
-- always nil despite the data file clearly containing a "hilsbrad"
-- entry - wrong key, not a rendering bug.
--
-- The REAL, currently-used data lives inline in Carbonite's own
-- Data/camelot/NxMapData.lua (lines 612-1330), under a header
-- explaining why it's a completely separate table from the file this
-- port originally copied:
--
--   "AUTO-GENERATED for WoW Forever ("camelot") from the wago.tools
--   DB2 of build 1.60.1.69893: generate_overlays.py --cache-dir
--   <db2> --all. Blizzard re-authored every vanilla zone map into
--   interface/worldmap/<zone>_c60, so the legacy name-keyed entries
--   would have drawn the old art on the new maps. Keys here are the
--   fileDataID lists of the overlay tiles and the renderer sets them
--   by ID (MapEngine: arTx path), so no texture folder is involved
--   and nothing has to be extracted from the client."
--
-- In other words: this specific server/client build re-exported every
-- zone's worldmap art under new internal IDs, and Carbonite ships a
-- SEPARATE, auto-generated table (this one) specifically to match -
-- the named-file-path convention (and the whole ExplorationOverlays.lua
-- file this port first copied) is categorically the wrong data source
-- for this build, not a one-zone exception. This is why UpdateOverlay
-- (MinimapEngine.lua) keeps its `arTx`/numeric-fileID branch as the
-- PRIMARY path, not a rare special case - every entry below uses it;
-- the named-file-path branch is now believed fully dead for this data
-- but kept harmless in code in case a future zone is added the old way.
--
-- Copied verbatim (including its one quirk: a handful of entries at
-- the end - hyjal/zephrasisle/riverlands/shendralas - aren't
-- "_c60"-suffixed, presumably zones this build didn't re-author or
-- that are Forever-custom to begin with, but still use the same
-- numeric-fileID convention as everything else here).
local AlchemyGPS = _G.AlchemyGPS
local Nx = AlchemyGPS
AlchemyGPS.Map = AlchemyGPS.Map or {}
local Map = Nx.Map

-- UIMapXMapArt -> WorldMapOverlay -> WorldMapOverlayTitle
Map.ZoneOverlays = {

-- AUTO-GENERATED for WoW Forever ("camelot") from the wago.tools DB2 of build
-- 1.60.1.69893:  generate_overlays.py --cache-dir <db2> --all
-- Blizzard re-authored every vanilla zone map into interface/worldmap/<zone>_c60,
-- so the legacy name-keyed entries would have drawn the old art on the new maps.
-- Keys here are the fileDataID lists of the overlay tiles and the renderer sets
-- them by ID (MapEngine: arTx path), so no texture folder is involved and
-- nothing has to be extracted from the client.
-- Value is "x,y,w,h"; the comment is subzone|uiMapID|grid.
-- Cities and battlegrounds have no overlays in DB2 and are absent here.

["durotar_c60"] = {
    ["8073637"] = "427,78,256,256", -- drygulchravine|5358|1x1
    ["8074089"] = "549,427,256,241", -- echoisles|5359|1x1
    ["8074090"] = "413,476,256,128", -- kolkarcrag|5360|1x1
    ["8074091,8074092"] = "244,0,512,256", -- orgrimmar|5361|2x1
    ["8074093"] = "432,170,256,256", -- razorhill|5362|1x1
    ["8074094"] = "301,189,256,256", -- razormanegrounds|5363|1x1
    ["8074095"] = "474,384,256,256", -- senjinvillage|5364|1x1
    ["8074096"] = "464,33,128,128", -- skullrock|5365|1x1
    ["8074097"] = "327,60,256,256", -- thunderridge|5366|1x1
    ["8074098"] = "462,286,256,256", -- tiragardekeep|5367|1x1
    ["8074099"] = "355,320,256,256", -- valleyoftrials|5368|1x1
},

["mulgore_c60"] = {
    ["7938948,7938949"] = "277,448,462,210", -- redcloudmesa|182|2x1
    ["7938946"] = "262,349,171,231", -- palemanerock|184|1x1
    ["7938945"] = "357,328,238,206", -- bloodhoofvillage|186|1x1
    ["7938961"] = "458,389,121,136", -- winterhoofwaterwell|188|1x1
    ["7938954"] = "494,381,253,151", -- therollingplains|190|1x1
    ["7938955"] = "509,279,227,214", -- theventurecomine|192|1x1
    ["7938947"] = "451,289,143,139", -- ravagedcaravan|194|1x1
    ["7938953"] = "419,170,220,214", -- thegoldenplains|196|1x1
    ["7938958"] = "369,266,151,158", -- thunderhornwaterwell|198|1x1
    ["7938944"] = "270,265,194,164", -- baeldundigsite|200|1x1
    ["7938956,7938957"] = "250,131,284,204", -- thunderbluff|202|2x1
    ["7938959"] = "339,71,159,157", -- wildmanewaterwell|204|1x1
    ["7938950"] = "496,119,180,181", -- redrocks|206|1x1
    ["7938960"] = "416,50,190,183", -- windfuryridge|208|1x1
    ["7938951,7938952"] = "218,0,303,225", -- skywatcher|4987|2x1
},

["barrens_c60"] = {
    ["8095985"] = "340,234,256,256", -- agamagor|5463|1x1
    ["8095986"] = "431,479,128,128", -- baelmodan|5464|1x1
    ["8095999"] = "335,462,256,128", -- blackthornridge|5465|1x1
    ["8096000"] = "555,0,128,128", -- boulderlodemine|5466|1x1
    ["8096001"] = "442,298,128,256", -- bramblescar|5467|1x1
    ["8096002"] = "365,350,256,128", -- camptaurajo|5468|1x1
    ["8096003"] = "419,63,128,128", -- deadmistpeak|5469|1x1
    ["8096004"] = "564,52,128,256", -- farwatchpost|5470|1x1
    ["8096005"] = "355,402,256,256", -- fieldofgiants|5471|1x1
    ["8096006"] = "492,63,128,128", -- groldomfarm|5472|1x1
    ["8096007"] = "306,130,128,128", -- honorsstand|5473|1x1
    ["8096008"] = "365,177,256,256", -- lushwateroasis|5474|1x1
    ["8096009"] = "527,307,256,128", -- northwatchhold|5475|1x1
    ["8096010"] = "507,294,128,128", -- raptorgrounds|5476|1x1
    ["8096011"] = "556,189,128,128", -- ratchet|5477|1x1
    ["8096012"] = "407,553,256,115", -- razorfendowns|5478|1x1
    ["8096013"] = "341,537,128,128", -- razorfenkraul|5479|1x1
    ["8096014"] = "481,211,256,128", -- stagnantoasis|5480|1x1
    ["8096015"] = "431,118,256,256", -- thecrossroads|5481|1x1
    ["8096016"] = "317,29,256,256", -- thedryhills|5482|1x1
    ["8096017"] = "384,115,128,128", -- theforgottenpools|5483|1x1
    ["8096018"] = "581,247,128,128", -- themerchantcoast|5484|1x1
    ["8096019"] = "412,0,128,128", -- themorshan|5485|1x1
    ["8096020"] = "456,0,256,128", -- thesludgefen|5486|1x1
    ["8096021"] = "498,119,256,128", -- thornhill|5487|1x1
},

["alterac_c60"] = {
    ["7975729,7975730,7975731,7975732"] = "626,253,376,384", -- chillwindpoint|5036|2x2
    ["7975733,7975734"] = "399,380,256,288", -- corrahnsdagger|5037|1x2
    ["7975735,7975736"] = "334,162,288,256", -- crushridgehold|5038|2x1
    ["7975744,7975745,7975746,7975747"] = "0,207,426,461", -- newdalaran|5039|2x2
    ["7975737,7975738"] = "276,0,288,256", -- dandredsfold|5040|2x1
    ["7975739"] = "406,279,256,256", -- gallowscorner|5041|1x1
    ["7975740"] = "225,478,256,190", -- gavinsnaze|5042|1x1
    ["7975741"] = "317,372,256,256", -- growlesscave|5043|1x1
    ["7975742,7975743"] = "196,131,256,288", -- mistyshore|5044|1x2
    ["7975748,7975749"] = "0,447,454,221", -- newlordamere|5045|2x1
    ["7975750"] = "270,197,256,256", -- ruinsofalterac|5046|1x1
    ["7975751,7975752"] = "462,307,256,320", -- soferasnaze|5047|1x2
    ["7975753,7975754,7975755,7975756"] = "549,105,384,320", -- strahnbrad|5048|2x2
    ["7975757"] = "314,471,256,197", -- theheadland|5049|1x1
    ["7975758"] = "462,77,256,256", -- theuplands|5050|1x1
},

["arathi_c60"] = {
    ["8039746"] = "432,362,256,256", -- boulderfisthall|5087|1x1
    ["8039747"] = "232,145,256,256", -- bouldergor|5088|1x1
    ["8039748"] = "558,112,256,256", -- circleofeastbinding|5089|1x1
    ["8039749"] = "286,310,256,256", -- circleofinnerbinding|5090|1x1
    ["8039750"] = "419,293,256,256", -- circleofouterbinding|5091|1x1
    ["8039751"] = "138,54,256,256", -- circleofwestbinding|5092|1x1
    ["8039752"] = "472,165,256,256", -- dabyriesfarmstead|5093|1x1
    ["8039753"] = "171,424,256,244", -- faldirscove|5094|1x1
    ["8039754"] = "531,276,256,256", -- goshekfarm|5095|1x1
    ["8039755"] = "656,119,256,256", -- hammerfall|5096|1x1
    ["8039756"] = "192,90,256,256", -- northfoldmanor|5097|1x1
    ["8039757"] = "370,186,256,256", -- refugepoint|5098|1x1
    ["8039758"] = "108,287,256,256", -- stromgardekeep|5099|1x1
    ["8039759"] = "355,412,256,256", -- thandolspan|5100|1x1
    ["8039760"] = "87,138,256,256", -- thoradinswall|5101|1x1
    ["8039761"] = "559,333,256,256", -- witherbarkvillage|5102|1x1
},

["badlands_c60"] = {
    ["7939140,7939141,7939142,7939143"] = "345,389,288,279", -- agmondsend|5213|2x2
    ["7939144"] = "325,148,256,256", -- angorfortress|5214|1x1
    ["7939145"] = "17,310,256,256", -- apocryphansrest|5215|1x1
    ["7939146,7939147"] = "501,341,256,288", -- campboff|5216|1x2
    ["7939148"] = "12,428,256,240", -- campcagg|5217|1x1
    ["7939149"] = "551,48,256,256", -- campkosh|5218|1x1
    ["7939150"] = "498,209,256,256", -- dustwindgulch|5219|1x1
    ["7939151"] = "445,121,256,256", -- hammertoesdigsite|5220|1x1
    ["7938928"] = "0,148,256,256", -- kargath|5221|1x1
    ["7939152,7939153,7939154,7939155"] = "611,110,384,512", -- lethlorravine|5222|2x2
    ["7939156,7939157"] = "148,384,288,256", -- mirageflats|5223|2x1
    ["7939158,7939159,7939160,7939161"] = "159,199,288,288", -- thedustbowl|5224|2x2
    ["7939162"] = "389,7,256,256", -- themakersterrace|5225|1x1
    ["7939163"] = "349,256,256,256", -- valleyoffangs|5226|1x1
},

["blastedlands_c60"] = {
    ["8040017"] = "310,133,256,256", -- altarofstorms|5103|1x1
    ["8040030"] = "361,15,256,256", -- dreadmaulhold|5104|1x1
    ["8040031"] = "361,195,256,256", -- dreadmaulpost|5105|1x1
    ["8040032"] = "472,9,256,256", -- garrisonarmory|5106|1x1
    ["8040033"] = "559,30,256,256", -- nethergardekeep|5107|1x1
    ["8040034"] = "405,123,256,256", -- riseofthedefiler|5108|1x1
    ["8040035"] = "501,140,256,256", -- serpentscoil|5109|1x1
    ["8040036,8040037"] = "453,259,288,256", -- thedarkportal|5110|2x1
    ["8040038,8040039,8040040,8040041"] = "212,178,384,490", -- thetaintedscar|5111|2x2
},

["tirisfal_c60"] = {
    ["7958233"] = "335,139,256,256", -- agamandmills|4997|1x1
    ["7958234"] = "630,326,256,256", -- balnirfarmstead|4998|1x1
    ["7958235,7958236"] = "584,139,256,288", -- brightwaterlake|4999|1x2
    ["7958237"] = "537,299,128,256", -- brill|5000|1x1
    ["7958238"] = "474,327,256,128", -- coldhearthmanor|5001|1x1
    ["7958239"] = "694,289,256,128", -- crusaderoutpost|5002|1x1
    ["7958240"] = "227,328,256,256", -- deathknell|5003|1x1
    ["7958241"] = "497,145,256,256", -- garrenshaunt|5004|1x1
    ["7958242"] = "746,125,256,256", -- monastary|5005|1x1
    ["7958243"] = "363,349,256,256", -- nightmarevale|5006|1x1
    ["7958244,7958245"] = "463,361,320,256", -- ruinsoflordaeron|5007|2x1
    ["7958246"] = "689,104,256,256", -- scarletwatchpost|5008|1x1
    ["7958247"] = "239,250,256,256", -- solidenfarmstead|5009|1x1
    ["7958248"] = "395,277,256,128", -- stillwaterpond|5010|1x1
    ["7958249"] = "698,362,256,256", -- thebulwark|5011|1x1
    ["7958262"] = "757,205,245,256", -- venomwebvale|5012|1x1
    ["7958263,7958264,7958265,7958266"] = "4,198,335,424", -- whisperingforest|5013|2x2
},

["silverpine_c60"] = {
    ["8064912"] = "494,262,256,256", -- ambermill|5198|1x1
    ["8064914"] = "491,417,256,251", -- berensperil|5199|1x1
    ["8064915"] = "470,261,256,256", -- deepelemmine|5200|1x1
    ["8064916"] = "593,74,256,256", -- fenrisisle|5201|1x1
    ["8064917"] = "465,0,256,256", -- maldensorchard|5202|1x1
    ["8064919"] = "323,128,256,128", -- northtideshollow|5203|1x1
    ["8064920"] = "382,252,256,256", -- olsensfarthing|5204|1x1
    ["8064922"] = "391,446,256,128", -- pyrewoodvillage|5205|1x1
    ["8064923"] = "364,359,256,256", -- shadowfangkeep|5206|1x1
    ["8064943"] = "402,65,256,256", -- thedeadfield|5207|1x1
    ["8064944"] = "457,144,256,256", -- thedecrepitferry|5208|1x1
    ["8064946"] = "379,446,256,222", -- thegreymanewall|5209|1x1
    ["8064947"] = "352,168,256,256", -- thesepulcher|5210|1x1
    ["8064949"] = "459,13,256,256", -- theshiningstrand|5211|1x1
    ["8064950"] = "286,37,256,256", -- theskitteringdark|5212|1x1
},

["westernplaguelands_c60"] = {
    ["8067724"] = "137,293,256,256", -- bulwark|5279|1x1
    ["8067725"] = "600,412,256,256", -- caerdarrow|5280|1x1
    ["8067726"] = "381,265,256,256", -- dalsonstears|5281|1x1
    ["8067727,8067728,8067729,8067730"] = "504,343,384,288", -- darrowmerelake|5282|2x2
    ["8067731"] = "300,311,256,128", -- felstonefield|5283|1x1
    ["8067732"] = "520,250,256,256", -- gahrronswithering|5284|1x1
    ["8067733,8067734,8067735,8067736"] = "307,16,384,288", -- hearthglen|5285|2x2
    ["8067737"] = "382,164,256,256", -- northridgelumbercamp|5286|1x1
    ["8067738,8067739"] = "260,355,288,256", -- ruinsofandorhol|5287|2x1
    ["8067740,8067741"] = "355,462,320,206", -- sorrowhill|5288|2x1
    ["8067742"] = "566,198,256,256", -- theweepingcave|5289|1x1
    ["8067743"] = "451,323,256,256", -- thewrithinghaunt|5290|1x1
    ["8067744,8067745"] = "590,86,256,384", -- thondrorilriver|5291|1x2
},

["easternplaguelands_c60"] = {
    ["7997922"] = "352,136,253,254", -- blackwoodlake|5051|1x1
    ["7997923"] = "417,259,226,216", -- corinscrossing|5052|1x1
    ["7997924"] = "218,313,242,206", -- crownguardtower|5053|1x1
    ["7997925"] = "213,405,231,231", -- darrowshire|5054|1x1
    ["7997938"] = "508,160,193,200", -- eastwalltower|5055|1x1
    ["7997939,7997940,7997941,7997942"] = "409,353,260,283", -- lakemereldar|5056|2x2
    ["7997943"] = "644,256,180,217", -- lightshopechapel|5057|1x1
    ["7997944,7997945,7997946,7997947"] = "678,202,324,466", -- newavalon|5058|2x2
    ["7997948"] = "544,62,227,234", -- northdale|5059|1x1
    ["7997949,7997950"] = "386,34,258,237", -- northpasstower|5060|2x1
    ["7997951,7997952,7997953,7997954"] = "125,28,361,289", -- plaguewood|5061|2x2
    ["7997955"] = "341,0,256,160", -- quellithienlodge|5062|1x1
    ["7997956,7997957"] = "18,0,419,174", -- stratholme|5063|2x1
    ["7997958,7997959"] = "11,19,228,313", -- terrordale|5064|1x2
    ["7997960,7997961"] = "203,186,273,244", -- thefungalvale|5065|2x1
    ["7997962"] = "534,247,207,255", -- theinfectisscar|5066|1x1
    ["7997963,7997964"] = "86,221,239,283", -- themarrisstead|5067|1x2
    ["7997965,7997966,7997967,7997968"] = "609,0,393,349", -- thenoxiousglade|5068|2x2
    ["7997969,7997970"] = "331,299,235,323", -- thepestilentscar|5069|1x2
    ["7997971,7997972"] = "111,399,231,259", -- theundercroft|5070|1x2
    ["7997973,7997974"] = "0,112,230,462", -- thondrorilriver|5071|1x2
    ["7997975,7997976,7997977,7997978"] = "542,366,286,289", -- tyrshand|5072|2x2
    ["7997979,7997980"] = "485,0,309,172", -- zulmashar|5073|2x1
},

["hillsbrad_c60"] = {
    ["8062819"] = "175,275,256,256", -- azureloadmine|5168|1x1
    ["8062820"] = "414,154,256,256", -- darrowhill|5169|1x1
    ["8062821,8062822"] = "637,294,256,288", -- dungarok|5170|1x2
    ["8062823,8062824,8062825,8062826"] = "605,75,384,384", -- durnholdekeep|5171|2x2
    ["8062827,8062828"] = "524,339,256,320", -- easternstrand|5172|1x2
    ["8062829,8062830,8062831,8062832"] = "198,155,320,288", -- hillsbradfields|5173|2x2
    ["8062845"] = "541,236,256,256", -- nethanderstead|5174|1x1
    ["8062846"] = "108,482,129,128", -- purgationisle|5175|1x1
    ["8062847,8062848"] = "2,192,288,256", -- southpointtower|5176|2x1
    ["8062849,8062850"] = "398,196,256,320", -- southshore|5177|1x2
    ["8062851,8062852"] = "509,0,256,320", -- tarrenmill|5178|1x2
    ["8062853,8062854"] = "208,368,288,256", -- westernstrand|5179|2x1
},

["hinterlands_c60"] = {
    ["8067557"] = "13,245,256,256", -- aeriepeak|5265|1x1
    ["8067558"] = "374,164,256,256", -- agolwatha|5266|1x1
    ["8067571"] = "171,306,256,256", -- hiriwatha|5267|1x1
    ["8067572,8067573"] = "505,333,256,288", -- jinthaalor|5268|1x2
    ["8067574"] = "158,149,256,256", -- plaguemistravine|5269|1x1
    ["8067575"] = "237,185,256,256", -- queldanillodge|5270|1x1
    ["8067576,8067577,8067578,8067579"] = "509,19,288,288", -- seradane|5271|2x2
    ["8067580"] = "240,387,256,256", -- shadraalor|5272|1x1
    ["8067581,8067582"] = "571,239,288,256", -- shaolwatha|5273|2x1
    ["8067583"] = "512,232,256,256", -- skulkrock|5274|1x1
    ["8067584"] = "373,365,256,256", -- thealtarofzul|5275|1x1
    ["8067585"] = "408,260,256,256", -- thecreepingruin|5276|1x1
    ["8067586,8067587"] = "693,303,256,320", -- theoverlookcliffs|5277|1x2
    ["8067588"] = "319,302,256,256", -- valorwindlake|5278|1x1
},

["dunmorogh_c60"] = {
    ["8061325"] = "573,280,128,128", -- amberstillranch|5125|1x1
    ["8061326"] = "155,403,256,256", -- anvilmar|5126|1x1
    ["8061327"] = "252,249,128,128", -- brewnallvillage|5127|1x1
    ["8061328"] = "274,296,256,128", -- chillbreezevalley|5128|1x1
    ["8061329"] = "295,385,256,128", -- coldridgepass|5129|1x1
    ["8061342"] = "217,287,128,128", -- frostmanehold|5130|1x1
    ["8061343"] = "166,184,256,256", -- gnomeragon|5131|1x1
    ["8061344"] = "608,291,256,256", -- golbolarquarry|5132|1x1
    ["8061345"] = "694,273,256,256", -- helmsbedlake|5133|1x1
    ["8061346"] = "281,167,128,256", -- iceflowlake|5134|1x1
    ["8061347,8061348"] = "397,163,320,256", -- ironforge|5135|2x1
    ["8061349"] = "386,294,256,256", -- kharanos|5136|1x1
    ["8061350"] = "502,221,128,256", -- mistypinerefuge|5137|1x1
    ["8061351"] = "759,173,128,256", -- northernoutpost|5138|1x1
    ["8061352"] = "347,163,128,256", -- shimmerridge|5139|1x1
    ["8061353"] = "792,279,128,128", -- southernoutpost|5140|1x1
    ["8061354"] = "314,311,256,256", -- thegrizzledden|5141|1x1
    ["8061355"] = "522,322,256,128", -- thetundridhills|5142|1x1
},

["searinggorge_c60"] = {
    ["8064749,8064750"] = "77,366,288,256", -- blackcharcave|5191|2x1
    ["8064751,8064752,8064753,8064754"] = "422,8,512,384", -- dustfirevalley|5192|2x2
    ["8064755,8064756,8064757,8064758"] = "85,30,512,512", -- firewatchridge|5193|2x2
    ["8064759,8064760"] = "494,300,320,256", -- grimesiltdigsite|5194|2x1
    ["8064773,8064774"] = "545,407,320,256", -- tannercamp|5195|2x1
    ["8064775,8064776,8064777,8064778"] = "250,170,512,384", -- thecauldron|5196|2x2
    ["8064779,8064780,8064781,8064782"] = "247,388,384,280", -- theseaofcinders|5197|2x2
},

["burningsteppes_c60"] = {
    ["8060538"] = "36,109,256,256", -- altarofstorms|5112|1x1
    ["8060539,8060540"] = "173,101,256,288", -- blackrockmountain|5113|1x2
    ["8060541,8060542,8060543,8060544"] = "589,279,288,320", -- blackrockpass|5114|2x2
    ["8060545,8060546"] = "334,114,256,288", -- blackrockstronghold|5115|1x2
    ["8060559,8060560,8060561,8060562"] = "56,258,512,320", -- dracodar|5116|2x2
    ["8060563"] = "707,168,256,256", -- dreadmaulrock|5117|1x1
    ["8060564,8060644,8060645,8060646"] = "708,311,294,288", -- morgansvigil|5118|2x2
    ["8060647,8060648,8060650,8060651"] = "377,285,320,288", -- pillarofash|5119|2x2
    ["8060652,8060653,8060654,8060656"] = "513,99,288,288", -- ruinsofthaurissan|5120|2x2
    ["8060657,8060658,8060659,8060660"] = "722,46,280,384", -- terrorwingpath|5121|2x2
},

["elwynn_c60"] = {
    ["8061955"] = "577,419,256,249", -- brackwellpumpkinpatch|5156|1x1
    ["8061956"] = "422,332,256,256", -- crystallake|5157|1x1
    ["8061957"] = "704,330,256,256", -- eastvaleloggingcamp|5158|1x1
    ["8061970"] = "238,428,256,240", -- fargodeepmine|5159|1x1
    ["8061971,8061972"] = "124,327,256,341", -- forestsedge|5160|1x2
    ["8061973"] = "250,270,256,256", -- goldshire|5161|1x1
    ["8061974"] = "425,431,256,237", -- jerodslanding|5162|1x1
    ["8061975"] = "381,147,256,256", -- northshirevalley|5163|1x1
    ["8061976,8061977"] = "696,435,306,233", -- ridgepointtower|5164|2x1
    ["8061978,8061979"] = "587,190,320,256", -- stonecairnlake|5165|2x1
    ["8061980,8061981,8061982,8061983"] = "0,0,512,512", -- stormwind|5166|2x2
    ["8061984"] = "551,292,256,256", -- towerofazora|5167|1x1
},

["deadwindpass_c60"] = {
    ["8060886,8060887,8060888,8060889"] = "249,76,384,384", -- deadmanscrossing|5122|2x2
    ["8060902,8060903"] = "269,337,320,256", -- karazhan|5123|2x1
    ["8060904,8060905,8060906,8060909"] = "426,299,288,288", -- thevice|5124|2x2
},

["duskwood_c60"] = {
    ["8061676,8061677"] = "55,342,288,256", -- addlesstead|5143|2x1
    ["8061678,8061679"] = "504,117,256,384", -- brightwoodgrove|5144|1x2
    ["8061680,8061681,8061682,8061683"] = "631,162,320,288", -- darkshire|5145|2x2
    ["8061696"] = "653,120,256,256", -- manormistmantle|5146|1x1
    ["8061697"] = "102,302,256,256", -- ravenhill|5147|1x1
    ["8061698,8061699,8061700,8061701"] = "85,149,384,320", -- ravenhillcemetary|5148|2x2
    ["8061702,8061703,8061704,8061705"] = "89,31,913,256", -- thedarkenedbank|5149|4x1
    ["8061706,8061707"] = "19,132,256,384", -- thehushedbank|5150|1x2
    ["8061708"] = "539,369,256,256", -- therottingorchard|5151|1x1
    ["8061709"] = "390,382,256,256", -- theyorgenfarmstead|5152|1x1
    ["8061710"] = "690,353,256,256", -- tranquilgardenscemetery|5153|1x1
    ["8061711,8061712,8061713,8061714"] = "298,79,384,512", -- twilightgrove|5154|2x2
    ["8061715,8061716"] = "243,348,256,288", -- vulgologremound|5155|1x2
},

["lochmodan_c60"] = {
    ["8063099,8063100,8063101,8063102"] = "309,310,320,358", -- grizzlepawridge|5180|2x2
    ["8063103,8063104"] = "482,321,384,256", -- ironbandsexcavationsite|5181|2x1
    ["8063117,8063118"] = "542,48,320,256", -- mogroshstronghold|5182|2x1
    ["8063119,8063120"] = "125,12,256,320", -- northgatepass|5183|1x2
    ["8063121,8063122"] = "229,11,256,320", -- silverstreammine|5184|1x2
    ["8063123,8063126"] = "215,348,256,320", -- stonesplintervalley|5185|1x2
    ["8063127,8063128"] = "339,11,320,256", -- stonewroughtdam|5186|2x1
    ["8063129,8063130,8063131,8063132"] = "546,199,384,320", -- thefarstriderlodge|5187|2x2
    ["8063133,8063134,8063135,8063136"] = "352,87,320,512", -- theloch|5188|2x2
    ["8063137"] = "217,203,256,256", -- thelsamar|5189|1x1
    ["8063138"] = "109,370,256,256", -- valleyofkings|5190|1x1
},

["redridge_c60"] = {
    ["7939758,7939759,7939760,7939761"] = "0,260,331,384", -- threecorners|361|2x2
    ["7939720,7939721,7939722,7939723"] = "118,324,462,324", -- lakeridgehighway|362|2x2
    ["7939713,7939715,7939716,7939717,7939718,7939719"] = "0,223,635,306", -- lakeeverstill|363|3x2
    ["7939724,7939725"] = "0,187,430,218", -- lakeshire|364|2x1
    ["7939726,7939727,7939728,7939729"] = "50,0,399,331", -- redridgecanyons|365|2x2
    ["7939742,7939743,7939744,7939745"] = "202,0,465,281", -- renderscamp|366|2x2
    ["7939703,7939704,7939705,7939706"] = "334,92,266,321", -- althersmill|367|2x2
    ["7939754,7939755,7939756,7939757"] = "436,88,287,442", -- stonewatchkeep|368|2x2
    ["7939746,7939747,7939748,7939749"] = "410,347,506,299", -- rendersvalley|369|2x2
    ["7939750,7939751,7939752,7939753"] = "538,266,464,329", -- stonewatchfalls|370|2x2
    ["7939707,7939708,7939709,7939712"] = "548,0,427,422", -- galardellvalley|371|2x2
},

["stranglethorn_c60"] = {
    ["8065937"] = "241,92,128,128", -- balalruins|5227|1x1
    ["8065938"] = "371,129,128,256", -- baliamahruins|5228|1x1
    ["8065939"] = "194,284,256,256", -- bloodsailcompound|5229|1x1
    ["8065940"] = "203,433,256,128", -- bootybay|5230|1x1
    ["8065941"] = "345,276,128,128", -- crystalveinmine|5231|1x1
    ["8065942"] = "260,132,128,128", -- gromgolbasecamp|5232|1x1
    ["8065943"] = "314,493,128,128", -- jagueroisle|5233|1x1
    ["8065944"] = "299,88,128,128", -- kalairuins|5234|1x1
    ["8065945"] = "388,0,256,256", -- kurzenscompound|5235|1x1
    ["8065946"] = "331,59,128,128", -- lakenazferiti|5236|1x1
    ["8065947"] = "280,368,128,128", -- mistvalevalley|5237|1x1
    ["8065948"] = "311,131,128,128", -- mizjahruins|5238|1x1
    ["8065949"] = "432,94,128,256", -- moshoggogremound|5239|1x1
    ["8065950"] = "211,359,128,128", -- nekmaniwellspring|5240|1x1
    ["8065951"] = "269,26,256,128", -- nesingwarysexpedition|5241|1x1
    ["8065952"] = "284,0,256,128", -- rebelcamp|5242|1x1
    ["8065953"] = "350,335,128,128", -- ruinsofaboraz|5243|1x1
    ["8065954"] = "306,301,128,128", -- ruinsofjubuwal|5244|1x1
    ["8065955"] = "196,3,128,256", -- ruinsofzulkunda|5245|1x1
    ["8065956"] = "394,212,256,128", -- ruinsofzulmamwe|5246|1x1
    ["8065969"] = "235,189,256,256", -- thearena|5247|1x1
    ["8065970"] = "152,90,256,256", -- thevilereef|5248|1x1
    ["8065979"] = "387,64,128,128", -- venturecobasecamp|5249|1x1
    ["8065972"] = "229,422,256,246", -- wildshore|5250|1x1
    ["8065973"] = "364,231,128,128", -- ziatajairuins|5251|1x1
    ["8065975"] = "156,42,128,128", -- zuuldalaruins|5253|1x1
},

["swampofsorrows_c60"] = {
    ["8067384,8067385,8067386,8067387"] = "492,0,384,320", -- fallowsanctuary|5254|2x2
    ["8067388"] = "0,262,256,256", -- ithariuscave|5255|1x1
    ["8067389,8067390,8067391"] = "746,0,256,668", -- mistyreedstrand|5256|1x3
    ["8067392,8067393"] = "0,140,256,320", -- mistyvalley|5257|1x2
    ["8067394,8067395,8067396,8067397"] = "565,218,320,288", -- pooloftears|5258|2x2
    ["8067398,8067399"] = "724,120,256,384", -- sorrowmurk|5259|1x2
    ["8067400,8067401"] = "129,236,288,256", -- splinterspearjunction|5260|2x1
    ["8067402,8067403"] = "552,378,384,256", -- stagalbog|5261|2x1
    ["8067404,8067405,8067406,8067407"] = "279,237,384,320", -- stonard|5262|2x2
    ["8067420"] = "171,145,256,256", -- theharborage|5263|1x1
    ["8067421,8067422"] = "286,110,320,256", -- theshiftingmire|5264|2x1
},

["westfall_c60"] = {
    ["8067794,8067795"] = "204,260,320,256", -- alexstonfarmstead|5292|2x1
    ["8067796"] = "208,375,256,256", -- demontsplace|5293|1x1
    ["8067800"] = "387,11,256,256", -- furlbrowspumpkinfarm|5294|1x1
    ["8067801"] = "220,102,256,256", -- goldcoastquarry|5295|1x1
    ["8067802"] = "307,29,256,256", -- jangolodemine|5296|1x1
    ["8067803"] = "317,331,256,256", -- moonbrook|5297|1x1
    ["8067804"] = "459,105,256,256", -- saldeansfarm|5298|1x1
    ["8067807"] = "442,241,256,256", -- sentinelhill|5299|1x1
    ["8067810"] = "339,418,256,250", -- thedaggerhills|5300|1x1
    ["8067815"] = "524,252,256,256", -- thedeadacre|5301|1x1
    ["8067816,8067817"] = "523,377,288,256", -- thedustplains|5302|2x1
    ["8067818"] = "488,0,256,256", -- thejansenstead|5303|1x1
    ["8067819"] = "328,148,256,256", -- themolsenfarm|5304|1x1
    ["8067820,8067821"] = "205,467,288,201", -- westfalllighthouse|5305|2x1
},

["wetlands_c60"] = {
    ["8068388"] = "347,218,256,256", -- angerfangencampment|5306|1x1
    ["8068389"] = "77,245,256,256", -- blackchannelmarsh|5307|1x1
    ["8068390"] = "89,142,256,256", -- bluegillmarsh|5308|1x1
    ["8068391"] = "507,115,256,256", -- direforgehill|5309|1x1
    ["8068392"] = "401,21,256,256", -- dunmodre|5310|1x1
    ["8068393,8068394,8068395,8068396"] = "611,230,384,384", -- grimbatol|5311|2x2
    ["8068397"] = "349,115,256,256", -- ironbeardstomb|5312|1x1
    ["8068398"] = "13,314,256,128", -- menethilharbor|5313|1x1
    ["8068399"] = "527,264,256,256", -- mosshidefen|5314|1x1
    ["8068400"] = "628,176,256,256", -- raptorridge|5315|1x1
    ["8068401"] = "237,41,256,256", -- saltsprayglen|5316|1x1
    ["8068402,8068403"] = "92,82,320,256", -- sundownmarsh|5317|2x1
    ["8068404"] = "456,125,256,256", -- thegreenbelt|5318|1x1
    ["8068405"] = "470,371,256,256", -- thelganrock|5319|1x1
    ["8068418"] = "247,205,256,256", -- whelgarsexcavationsite|5320|1x1
},

["teldrassil_c60"] = {
    ["8095477"] = "382,281,256,256", -- banethilhollow|5452|1x1
    ["8095478,8095479"] = "101,247,320,256", -- darnassus|5453|2x1
    ["8095480"] = "462,323,256,128", -- dolanaar|5454|1x1
    ["8095481"] = "368,443,256,128", -- gnarlpinehold|5455|1x1
    ["8095482"] = "436,380,256,256", -- lakealameth|5456|1x1
    ["8095483"] = "335,313,128,256", -- poolsofarlithrien|5457|1x1
    ["8095484"] = "494,548,128,120", -- ruttheranvillage|5458|1x1
    ["8095485"] = "491,153,256,256", -- shadowglen|5459|1x1
    ["8095486"] = "561,292,256,256", -- starbreezevillage|5460|1x1
    ["8095500"] = "272,127,256,256", -- theoracleglade|5461|1x1
    ["8095501"] = "377,93,256,256", -- wellspringlake|5462|1x1
},

["darkshore_c60"] = {
    ["8085570"] = "324,306,256,256", -- ametharan|5385|1x1
    ["8085571"] = "318,162,256,256", -- auberdine|5386|1x1
    ["8085572"] = "365,181,256,256", -- bashalaran|5387|1x1
    ["8085573"] = "375,94,256,256", -- cliffspringriver|5388|1x1
    ["8085586"] = "305,412,256,256", -- groveoftheancients|5389|1x1
    ["8085587"] = "229,485,256,183", -- remtravelsexcavation|5390|1x1
    ["8085588"] = "510,0,256,256", -- ruinsofmathystra|5391|1x1
    ["8085589"] = "329,508,256,160", -- themastersglaive|5392|1x1
    ["8085590"] = "468,85,256,256", -- towerofalthalaxx|5393|1x1
},

["ashenvale_c60"] = {
    ["8073181"] = "272,251,256,256", -- astranaar|5321|1x1
    ["8073182"] = "856,151,146,256", -- boughshadow|5322|1x1
    ["8073183"] = "547,426,256,242", -- fallenskylake|5323|1x1
    ["8073184"] = "713,344,256,256", -- felfirehill|5324|1x1
    ["8073185"] = "189,324,256,256", -- firescarshrine|5325|1x1
    ["8073186"] = "392,218,256,256", -- irislake|5326|1x1
    ["8073187"] = "131,137,128,256", -- lakefalathim|5327|1x1
    ["8073188,8073190"] = "205,38,256,320", -- maestraspost|5328|1x2
    ["8073191,8073192"] = "356,347,288,256", -- mystrallake|5329|2x1
    ["8073193"] = "597,258,256,256", -- nightrun|5330|1x1
    ["8073194"] = "520,238,256,256", -- raynewoodretreat|5331|1x1
    ["8073195,8073196"] = "694,225,288,256", -- satyrnaar|5332|2x1
    ["8073197"] = "463,141,256,256", -- thehowlingvale|5333|1x1
    ["8073198"] = "260,373,256,256", -- theruinsofstardust|5334|1x1
    ["8073199"] = "104,259,256,256", -- theshrineofaessina|5335|1x1
    ["8073200"] = "19,28,256,256", -- thezoramstrand|5336|1x1
    ["8073201"] = "203,158,256,256", -- thislefurvillage|5337|1x1
    ["8073202"] = "796,311,206,256", -- warsonglumbercamp|5338|1x1
},

["thousandneedles_c60"] = {
    ["8096360,8096361,8096362,8096363"] = "0,0,320,320", -- campethok|5488|2x2
    ["8096364"] = "259,131,256,256", -- darkcloudpinnacle|5489|1x1
    ["8096365"] = "357,264,256,256", -- freewindpost|5490|1x1
    ["8096366"] = "31,155,256,256", -- highperch|5491|1x1
    ["8096367"] = "391,192,256,256", -- splithoofcrag|5492|1x1
    ["8096368"] = "205,70,256,256", -- thegreatlift|5493|1x1
    ["8096369"] = "179,200,256,256", -- thescreechingcanyon|5494|1x1
    ["8096370,8096371,8096372,8096373"] = "610,300,320,368", -- theshimmeringflats|5495|2x2
    ["8096386"] = "492,250,256,256", -- windbreakcanyon|5496|1x1
},

["stonetalonmountain_c60"] = {
    ["8094123"] = "572,561,256,107", -- boulderslideravine|5421|1x1
    ["8094124"] = "718,571,256,97", -- campaparaje|5422|1x1
    ["8094125"] = "668,515,256,128", -- grimtotempost|5423|1x1
    ["8094126"] = "663,582,128,86", -- malakajin|5424|1x1
    ["8094127"] = "390,145,256,256", -- mirkfallonlake|5425|1x1
    ["8094128"] = "475,433,128,128", -- sishircanyon|5426|1x1
    ["8094141,8094142"] = "247,0,288,256", -- stonetalonpeak|5427|2x1
    ["8094143"] = "389,320,256,256", -- sunrockretreat|5428|1x1
    ["8094144,8094145"] = "210,234,256,384", -- thecharredvale|5429|1x2
    ["8094146,8094147,8094148,8094149"] = "457,282,288,384", -- webwinderpath|5430|2x2
    ["8094150,8094151,8094152,8094153"] = "553,197,320,288", -- windshearcrag|5431|2x2
},

["desolace_c60"] = {
    ["7963797"] = "311,61,256,256", -- ethelrethor|5014|1x1
    ["7963798"] = "293,426,256,242", -- gelkisvillage|5015|1x1
    ["7963799,7963800"] = "387,244,288,256", -- kodograveyard|5016|2x1
    ["7963801"] = "607,215,256,256", -- kolkarvillage|5017|1x1
    ["7963802"] = "555,181,256,256", -- kormekshut|5018|1x1
    ["7963803,7963804"] = "590,365,256,288", -- magramvillage|5019|1x2
    ["7963805,7963806,7963807,7963808"] = "399,380,288,288", -- mannoroccoven|5020|2x2
    ["7963809"] = "554,0,256,256", -- nijelspoint|5021|1x1
    ["7963810"] = "241,6,128,128", -- ranazjarisle|5022|1x1
    ["7963811,7963812,7963813,7963814"] = "598,10,360,328", -- sargeron|5023|2x2
    ["7963815"] = "690,444,256,224", -- shadowbreakravine|5024|1x1
    ["7963816"] = "167,389,256,256", -- shadowpreyvillage|5025|1x1
    ["7963817"] = "431,0,256,256", -- tethrisaran|5026|1x1
    ["7963818"] = "447,102,256,256", -- thunderaxefortress|5027|1x1
    ["7963819,7963820"] = "212,215,256,288", -- valleyofspears|5028|1x2
},

["feralas_c60"] = {
    ["8078745"] = "689,233,256,256", -- campmojache|5369|1x1
    ["8078746"] = "454,201,256,256", -- diremaul|5370|1x1
    ["8078759"] = "486,329,128,128", -- feralscarvale|5371|1x1
    ["8078760"] = "478,386,128,256", -- frayfeatherhighlands|5372|1x1
    ["8078761"] = "690,141,256,256", -- gordunnioutpost|5373|1x1
    ["8078762"] = "623,167,128,256", -- grimtotemcompound|5374|1x1
    ["8078763,8078764"] = "192,375,256,293", -- isleofdread|5375|1x2
    ["8078765"] = "751,198,251,256", -- lowerwilds|5376|1x1
    ["8078766"] = "493,70,128,128", -- oneiros|5377|1x1
    ["8078767"] = "540,320,256,256", -- ruinsofisildien|5378|1x1
    ["8078768"] = "305,0,256,256", -- ruinsofravenwind|5379|1x1
    ["8078769"] = "208,234,256,256", -- sardorisle|5380|1x1
    ["8078770"] = "454,0,256,128", -- thedreambough|5381|1x1
    ["8078771,8078772"] = "404,256,256,320", -- theforgottencoast|5382|1x2
    ["8078773,8078774"] = "319,75,288,256", -- thetwincolossals|5383|2x1
    ["8078775"] = "618,298,256,256", -- thewrithingdeep|5384|1x1
},

["dustwallowmarsh_c60"] = {
    ["8085988"] = "660,21,256,256", -- alcazisland|5394|1x1
    ["8085989,8085990"] = "239,189,512,256", -- backbaywetlands|5395|2x1
    ["8085991,8085992,8085993,8085994"] = "230,0,288,288", -- brackenwallvillage|5396|2x2
    ["8086007"] = "257,313,256,256", -- thedenofflame|5397|1x1
    ["8086008"] = "534,224,256,256", -- theramore|5398|1x1
    ["8086009,8086010"] = "367,381,288,256", -- thewyrmbog|5399|2x1
    ["8086011,8086012"] = "422,0,256,320", -- witchhill|5400|1x2
},

["tanaris_c60"] = {
    ["8095031"] = "363,194,256,256", -- abyssalsands|5432|1x1
    ["8095032"] = "473,234,128,256", -- brokenpillar|5433|1x1
    ["8095033"] = "561,256,256,256", -- cavernsoftime|5434|1x1
    ["8095034"] = "325,289,256,256", -- dunemaulcompound|5435|1x1
    ["8095035"] = "395,346,256,256", -- eastmoonruins|5436|1x1
    ["8095036"] = "421,91,256,256", -- gadgetzan|5437|1x1
    ["8095037"] = "445,511,256,157", -- landsendbeach|5438|1x1
    ["8095038"] = "629,220,256,256", -- lostriggercove|5439|1x1
    ["8095039"] = "533,104,128,256", -- noonshaderuins|5440|1x1
    ["8095040"] = "299,100,256,256", -- sandsorrowwatch|5441|1x1
    ["8095041"] = "499,293,256,256", -- southbreakshore|5442|1x1
    ["8095042"] = "323,359,256,256", -- southmoonruins|5443|1x1
    ["8095043"] = "592,75,256,256", -- steamwheedleport|5444|1x1
    ["8095056"] = "449,372,256,256", -- thegapingchasm|5445|1x1
    ["8095057"] = "252,199,256,256", -- thenoxiouslair|5446|1x1
    ["8095058"] = "203,286,256,256", -- thistleshrubvalley|5447|1x1
    ["8095059"] = "291,434,256,234", -- valleyofthewatchers|5448|1x1
    ["8095060"] = "509,168,256,256", -- waterspringfield|5449|1x1
    ["8095061"] = "611,147,128,256", -- zalashjisden|5450|1x1
    ["8095062"] = "254,0,256,256", -- zulfarrak|5451|1x1
},

["azshara_c60"] = {
    ["8073311,8073312,8073313,8073377"] = "479,201,288,320", -- bayofstorms|5339|2x2
    ["8073442"] = "644,40,256,256", -- bitterreaches|5340|1x1
    ["8073517"] = "191,369,256,256", -- forlornridge|5341|1x1
    ["8073586"] = "77,331,256,256", -- haldarrencampment|5342|1x1
    ["8073612,8073613,8073614"] = "366,0,576,256", -- jaggedreef|5343|3x1
    ["8073615,8073616"] = "296,429,320,239", -- lakemennar|5344|2x1
    ["8073617"] = "478,44,256,256", -- legashencampment|5345|1x1
    ["8073619"] = "552,499,256,128", -- ravencrestmonument|5346|1x1
    ["8073620,8073621,8073622,8073623"] = "238,221,288,288", -- ruinsofeldarath|5347|2x2
    ["8073624"] = "35,422,256,246", -- shadowsongshrine|5348|1x1
    ["8073625,8073626"] = "389,353,384,256", -- southridgebeach|5349|2x1
    ["8073627"] = "681,153,256,256", -- templeofarkkoran|5350|1x1
    ["8073628"] = "499,119,256,256", -- thalassianbasecamp|5351|1x1
    ["8073629,8073630"] = "396,540,512,128", -- theruinedreaches|5352|2x1
    ["8073631"] = "404,194,256,256", -- theshatteredstrand|5353|1x1
    ["8073632,8073633"] = "250,106,256,288", -- timbermawhold|5354|1x2
    ["8073634"] = "818,107,128,256", -- towerofeldara|5355|1x1
    ["8073635"] = "422,95,256,256", -- ursolan|5356|1x1
    ["8073636"] = "84,229,256,256", -- valormok|5357|1x1
},

["felwood_c60"] = {
    ["8093156"] = "292,263,256,256", -- bloodvenomfalls|5401|1x1
    ["8093157"] = "408,533,256,135", -- deadwoodvillage|5402|1x1
    ["8093158"] = "405,429,256,239", -- emeraldsanctuary|5403|1x1
    ["8093159"] = "483,0,256,256", -- felpawvillage|5404|1x1
    ["8093172"] = "420,54,256,256", -- irontreewoods|5405|1x1
    ["8093173"] = "332,465,256,203", -- jadefireglen|5406|1x1
    ["8093174"] = "330,29,256,256", -- jadefirerun|5407|1x1
    ["8093175"] = "271,331,256,128", -- jaedenar|5408|1x1
    ["8093176"] = "496,509,256,159", -- morlosaran|5409|1x1
    ["8093177"] = "297,381,256,256", -- ruinsofconstellas|5410|1x1
    ["8093178"] = "307,123,256,256", -- shatterscarvale|5411|1x1
    ["8093179"] = "548,90,256,256", -- talonbranchglade|5412|1x1
},

["ungorocrater_c60"] = {
    ["8097029,8097030,8097031,8097032"] = "367,178,320,288", -- fireplumeridge|5497|2x2
    ["8097033,8097034,8097035,8097036"] = "121,151,320,384", -- golakkahotsprings|5498|2x2
    ["8097037,8097038,8097039,8097040"] = "582,67,288,288", -- ironstoneplateau|5499|2x2
    ["8097041,8097042,8097043,8097044,8097045,8097046"] = "160,6,576,288", -- lakkaritarpits|5500|3x2
    ["8097047,8097048,8097049,8097050"] = "158,368,384,288", -- terrorrun|5501|2x2
    ["8097051,8097052,8097053,8097054"] = "560,240,320,384", -- themarshlands|5502|2x2
    ["8097055,8097056,8097057,8097058"] = "367,380,384,288", -- theslitheringscar|5503|2x2
},

["moonglade_c60"] = {
    ["8093181,8093182,8093183,8093184,8093185,8093186"] = "244,89,576,512", -- lakeeluneara|5413|3x2
},

["silithus_c60"] = {
    ["8093548,8093549,8093550,8093586"] = "264,11,512,320", -- hiveashi|5414|2x2
    ["8093679,8093771,8093873,8093939"] = "244,284,512,384", -- hiveregal|5415|2x2
    ["8093940,8093941,8093942,8093943"] = "96,143,384,512", -- hivezora|5416|2x2
    ["8093956,8093957,8093958,8093959"] = "499,64,384,384", -- southwindvillage|5417|2x2
    ["8093960,8093961,8093962,8093963"] = "103,23,320,288", -- thecrystalvale|5418|2x2
    ["8093964,8093965"] = "115,412,288,256", -- thescarabwall|5419|2x1
    ["8093966,8093967"] = "343,196,320,256", -- twilightbasecamp|5420|2x1
},

["winterspring_c60"] = {
    ["8097071"] = "447,441,256,227", -- darkwhispergorge|5504|1x1
    ["8097072"] = "509,107,256,256", -- everlook|5505|1x1
    ["8097073"] = "222,172,256,256", -- frostfirehotsprings|5506|1x1
    ["8097074"] = "368,7,256,256", -- frostsaberrock|5507|1x1
    ["8097075"] = "523,376,256,256", -- frostwhisperravine|5508|1x1
    ["8097076"] = "611,242,128,256", -- icethistlehills|5509|1x1
    ["8097077"] = "401,198,256,256", -- lakekeltheril|5510|1x1
    ["8097078"] = "493,258,256,256", -- mazthoril|5511|1x1
    ["8097079"] = "593,340,256,256", -- owlwingthicket|5512|1x1
    ["8097080"] = "392,137,256,256", -- starfallvillage|5513|1x1
    ["8097081"] = "555,27,256,256", -- thehiddengrove|5514|1x1
    ["8097082"] = "229,243,256,128", -- timbermawpost|5515|1x1
    ["8097083"] = "617,158,256,128", -- winterfallvillage|5516|1x1
},

["alteracvalley_c60"] = {
    ["8097530,8097531"] = "348,13,288,256", -- dunbaldar|5517|2x1
    ["8097532,8097533"] = "399,375,256,293", -- frostwolfkeep|5518|1x2
    ["8097534,8097535,8097536,8097537"] = "335,172,320,320", -- icebloodgarrison|5519|2x2
},

["hyjal"] = {
    ["7950773,7950774,7950775,7950776"] = "195,110,321,362", -- cradleoftranquility|4988|2x2
    ["7950777,7950778,7950779,7950780"] = "379,79,361,334", -- daegun|4989|2x2
    ["7950781,7950782,7950783,7950784"] = "0,197,258,338", -- elderwild|4990|2x2
    ["7950785,7950786,7950787,7950788"] = "313,381,307,287", -- felbloodscar|4991|2x2
    ["7950789,7950790,7950791,7950792"] = "42,363,430,305", -- malornesretreat|4992|2x2
    ["7950793"] = "138,213,218,247", -- mourningsrest|4993|1x1
    ["7950794"] = "380,285,254,214", -- shrineofaviana|4994|1x1
    ["7950795,7950796,7950797,7950798"] = "612,69,390,395", -- summitofeternity|4995|2x2
    ["7950799,7950800,7950801,7950802"] = "488,328,502,340", -- taintedfoothills|4996|2x2
},

["zephrasisle"] = {
    ["8124653"] = "600,357,209,191", -- eastpylonwatchtower|5520|1x1
    ["8124654"] = "460,453,146,180", -- fairweatherstables|5521|1x1
    ["8124655"] = "415,289,141,147", -- falaathvillage|5522|1x1
    ["8124656"] = "457,339,158,141", -- overlookstandingstones|5523|1x1
    ["8124657"] = "652,222,227,239", -- rohashispires|5524|1x1
    ["8124658,8124659"] = "475,14,237,265", -- ruinsofbanaethal|5525|1x2
    ["8124660,8124661"] = "494,122,290,217", -- shadowgaleforest|5526|2x1
    ["8124662,8124663,8124664,8124665"] = "248,192,302,257", -- shendarvillage|5527|2x2
    ["8124666"] = "526,252,207,185", -- shrineofakir|5528|1x1
    ["8124667,8124668,8124669,8124670"] = "250,22,325,267", -- thendalgrove|5529|2x2
    ["8124671,8124672,8124673,8124674"] = "479,332,302,336", -- valanaar|5530|2x2
    ["8124675"] = "298,351,198,152", -- westpylonwatchtower|5531|1x1
    ["8124676,8124677"] = "350,372,212,271", -- windfieldorchard|5532|1x2
    ["8124678"] = "398,230,207,206", -- windsonglake|5533|1x1
    ["8124679"] = "381,169,194,150", -- windsongstandingstones|5534|1x1
},

["riverlands"] = {
    ["8032430,8032431,8032432,8032433"] = "493,0,277,291", -- bolderok|5074|2x2
    ["8032436,8032437,8032438,8032439"] = "25,320,382,302", -- bristlehills|5075|2x2
    ["8032440"] = "544,427,241,241", -- farholdekeep|5076|1x1
    ["8032441,8032442,8032443,8032444"] = "309,0,334,313", -- kroldokstronghold|5077|2x2
    ["8032445,8032446,8032447,8032448"] = "292,407,338,261", -- meadowsbrook|5078|2x2
    ["8032449,8032450,8032451,8032452"] = "625,266,261,310", -- powderfuseport|5079|2x2
    ["8032453"] = "504,215,213,200", -- rogmar|5080|1x1
    ["8032454,8032455"] = "371,215,230,274", -- sunnyglade|5081|1x2
    ["8032456"] = "499,330,220,186", -- terralswatch|5082|1x1
    ["8032457"] = "292,291,182,210", -- turnersloggingcamp|5083|1x1
    ["8032458,8032459,8032460,8032461"] = "125,98,343,314", -- twilightsshroud|5084|2x2
    ["8032462"] = "444,413,228,195", -- wheelersgrange|5085|1x1
    ["8032463,8032464,8032465,8032466"] = "633,52,323,318", -- windstead|5086|2x2
},

["shendralas"] = {
    ["7970575,7970581,7970582,7970583"] = "583,0,334,415", -- bristlebackretreat|5029|2x2
    ["7970620,7970621,7970622,7970623"] = "339,180,327,488", -- buildings|5030|2x2
    ["7970584,7970585,7970586,7970587"] = "150,178,316,301", -- evenshadeoverlook|5031|2x2
    ["7970588,7970589,7970590,7970591"] = "570,323,317,331", -- forlorngardens|5032|2x2
    ["7970592,7970593"] = "495,255,257,229", -- magramfront|5033|2x1
    ["7970594,7970595,7970596,7970597"] = "125,362,344,306", -- outcasthideaway|5034|2x2
    ["7970612,7970613,7970614,7970615,7970616,7970617"] = "81,0,620,344", -- valleyofbones|5035|3x2
},
}
