import matplotlib.pyplot as plt
import numpy as np


# FilterBlogCompileTimes
width = 0.25
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

tot = [2.4763457775115967,2.4798877239227295,2.492201566696167,2.477468729019165,2.5222277641296387,2.5122578144073486,2.579533100128174]

tot_std_lb = [2.431425839364206,2.424893039978896,2.428376855522338,2.4279375176254256,2.477964917463084,2.4535700640418434,2.446750356597901]
tot_std_ub = [2.6037552591499273,2.532022179645941,2.5923903563917245,2.525194370022415,2.5719998283763528,2.5811512045060625,2.636505570170084]

solver = [1.680224205,1.6710066559999999,1.661507599,1.657419303,1.6937210820000002,1.7057379700000002,1.763435513]

solver_std_lb = [1.6364599883073974,1.6063177856108186,1.5751566073683283,1.5990164348400144,1.651269660305508,1.649585903578315,1.6392235267385031]
solver_std_ub = [1.791742598137047,1.7227313063891814,1.7201046617427824,1.7082858491599855,1.7585561703611592, 1.7630623073105736, 1.8344043452614966]


t_compile = [element1 - element2 for (element1, element2) in zip(tot, solver)]

error_compile_ub = [element1 - element2 for (element1, element2) in zip(tot_std_ub, solver_std_ub)]
error_compile_lb = [element1 - element2 for (element1, element2) in zip(tot_std_lb, solver_std_lb)]

delta_error_compile = [abs(element1 - element2) for (element1, element2) in zip(error_compile_ub, error_compile_lb)]
delta_error_solver  = [0] * 7 #[element1 - element2 for (element1, element2) in zip(tot_std_ub, tot_std_lb)]

#Gibbon
tot_compile_gibbon = [0.8607304096221924,0.859238862991333,0.8573410511016846,0.8580596446990967,0.8600566387176514,0.852698564529419,0.8588204383850098]
gibbon_lb = [0.852443202277915,0.8498290087198315,0.8397840946837096,0.8522387271071532,0.8587618256234751,0.836141325873412,0.8478211033878086,]
gibbon_ub = [0.8649528980842268,0.86187058302279,0.8594348142620098,0.8624391365436985,0.8612693298568038,0.8591973471883828,0.8630075717763083] 

#marmoset greedy 
tot_compile_greedy = [0.8232002258300781,0.7986009120941162,0.8631477355957031,0.8088064193725586,0.809377908706665,0.8230295181274414,0.8146462440490723]
greedy_lb = [0.8148159157009246,0.7805803182774125,0.8506619539874934,0.79823302307509,0.7933506167162483,0.8102714431176877,0.8019911534346515] 
greedy_ub = [0.824345088259579,0.8143934048162562,0.8672989864794932,0.8179191574906381,0.8199436668327427,0.826059744236506,0.8230051378318957]

delta_error_gibbon = [element1 - element2 for (element1, element2) in zip(gibbon_ub, gibbon_lb)]

delta_error_greedy = [element1 - element2 for (element1, element2) in zip(greedy_ub, greedy_lb)]

plt.ylim([0, 6])

# Stacked bar chart, gibbon
ax.bar(values, tot_compile_gibbon, yerr = delta_error_gibbon , width=width, ecolor = 'black', color= 'green', error_kw=dict(lw=1, capsize=2, capthick=1))

#Stacked bar chart greedy 
ax.bar(values + width, tot_compile_greedy, yerr = delta_error_greedy , width=width, ecolor = 'black', color= 'yellow', error_kw=dict(lw=1, capsize=2, capthick=1))

# Stacked bar chart, marmoset
ax.bar(values + width*2 , t_compile, yerr = delta_error_solver  , width=width, ecolor = 'black', color= 'blue')
ax.bar(values + width*2, solver, yerr = delta_error_compile , width=width, ecolor = 'black', bottom = t_compile, color= 'red', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Time in Seconds", fontsize ='36')

plt.yticks(fontsize='32')

Legend = ['gibbon', 'marmoset greedy', 'marmoset - (solver + IO) ', 'solver + IO']

ax.legend(Legend, loc = 2, fontsize=32)

fig.set_size_inches(16, 8)                                                                                                                                    
plt.savefig('FilterBlogCompileTimes.pdf', dpi=4000, format='pdf', bbox_inches='tight')
#plt.show() 



# ContentSearchCompileTimes
width = 0.25
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

tot = [6.081379175186157,6.06399941444397,6.234234809875488,6.1213698387146,6.181093215942383,6.262093782424927,6.169062376022339]

tot_std_lb = [5.998436550160607,5.941136302864032,6.056734238303654,6.035853765428769,6.112343071597323,6.056516202216304,6.025754126992353]
tot_std_ub = [6.233867705007036,6.176806666140281,6.430480962756323, 6.268578573709686,6.279620410305753,6.375389544243657,6.363005697972382]

solver = [5.242176141,5.1773923250000005,5.354751968,5.223972439,5.275005103,5.368839304999999,5.249520898]

solver_std_lb = [5.1220051520955625,5.071235740306588,5.181306244559707,5.127580895361574,5.2212114340546885,5.155611325696527,5.107882930327245]
solver_std_ub = [5.351551019237773,5.275431983693413,5.532472068551405,5.3644265761939804,5.381269163945311,5.479814418970139, 5.455961354561646]


t_compile = [element1 - element2 for (element1, element2) in zip(tot, solver)]

#error_compile_ub = [element1 - element2 for (element1, element2) in zip(tot_std_ub, solver_std_ub)]
#error_compile_lb = [element1 - element2 for (element1, element2) in zip(tot_std_lb, solver_std_lb)]

delta_error_compile = [element1 - element2 for (element1, element2) in zip(tot_std_ub, tot_std_lb)]
delta_error_solver  = [0] * 7

#Gibbon
tot_compile_gibbon = [0.9083178043365479,0.9101319313049316,0.921332836151123,0.9051344394683838,0.91864013671875,0.9229867458343506,0.9178578853607178]
gibbon_lb = [0.9022814308169638,0.885252554510956,0.9131939656276613,0.8953648456312211,0.9038066579273588,0.9063729696602817,0.901092830844145]
gibbon_ub = [0.9151587610877401,0.9181514588048807,0.9264136440152153,0.9157871357225387,0.9221932378042493,0.9262777447901306,0.9206766715836978] 

#marmoset greedy 
tot_compile_greedy = [0.9009778499603271,0.8970122337341309,0.893225908279419,0.8943295478820801,0.8910129070281982,0.8961613178253174,0.8922576904296875]
greedy_lb = [0.8913367329231676,0.880767896610307,0.8798558221570603,0.8902103157697545,0.8727383124015266,0.8892640770100962,0.8892640770100962,0.8757294321434738] 
greedy_ub = [0.906987057309173,0.9033215627029798,0.9021972775811666,0.8957687962195846,0.8952015730558301,0.9023875957770403,0.8998111846337343]



delta_error_gibbon = [element1 - element2 for (element1, element2) in zip(gibbon_ub, gibbon_lb)]

delta_error_greedy = [element1 - element2 for (element1, element2) in zip(greedy_ub, greedy_lb)]

plt.ylim([0, 14])

# Stacked bar chart, gibbon
ax.bar(values, tot_compile_gibbon, yerr = delta_error_gibbon , width=width, ecolor = 'black', color= 'green', error_kw=dict(lw=1, capsize=2, capthick=1))

#Stacked bar chart greedy 
ax.bar(values + width, tot_compile_greedy, yerr = delta_error_greedy , width=width, ecolor = 'black', color= 'yellow', error_kw=dict(lw=1, capsize=2, capthick=1))

# Stacked bar chart, marmoset
ax.bar(values + width*2 , t_compile, yerr = delta_error_solver , width=width, ecolor = 'black', color= 'blue')
ax.bar(values + width*2, solver, yerr = delta_error_compile , width=width, ecolor = 'black', bottom = t_compile, color= 'red', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Time in Seconds", fontsize ='36')

plt.yticks(fontsize='32')

Legend = ['gibbon', 'marmoset greedy', 'marmoset - (solver + IO) ', 'solver + IO']

ax.legend(Legend, loc = 2, fontsize=32)

fig.set_size_inches(16, 8)                                                                                                                                    
plt.savefig('ContentSearchCompileTimes.pdf', dpi=4000, format='pdf', bbox_inches='tight')
#plt.show() 


#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


#TagSearchCompileTimes
width = 0.25
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

tot = [7.2059361934661865,7.346128940582275,7.281888723373413,7.591944456100464,7.1686179637908936,7.332003116607666,7.263138055801392]

tot_std_lb = [7.062782871756884,7.116351133602505,7.07569103097135,7.477315059293655,7.072487588607124,7.207674328579598,7.146516855719437]
tot_std_ub = [7.371132849288717,7.403958208675869, 7.40285548248012, 7.723281485184019,7.297944735272542,7.475319030456317,7.479295197960983]

solver = [6.257179876,6.369001831999999,6.336062887000001,6.7323154800000005,6.242812315,6.361802778,6.328930246]

solver_std_lb = [6.121274403056076,6.170748797571678,6.145702238963185,6.571989770757389,6.141317742880025,6.234596492857011,6.2050361348444145]
solver_std_ub = [6.4044208273883685,6.467482173983878, 6.4847974483701485,6.846211699687055,6.341438445564419,6.518163150920768,6.525735220266695]


t_compile = [element1 - element2 for (element1, element2) in zip(tot, solver)]

error_compile_ub = [element1 - element2 for (element1, element2) in zip(tot_std_ub, solver_std_ub)]
error_compile_lb = [element1 - element2 for (element1, element2) in zip(tot_std_lb, solver_std_lb)]

delta_error_compile = [element1 - element2 for (element1, element2) in zip(tot_std_ub, tot_std_lb)]
delta_error_solver  = [0] * 7 #[element1 - element2 for (element1, element2) in zip(tot_std_ub, tot_std_lb)]

#Gibbon
tot_compile_gibbon = [0.9700431823730469,0.9678890705108643,0.9738900661468506,0.9320886135101318,0.9801414012908936,0.9762258529663086,0.9723186492919922]
gibbon_lb = [0.9484352364840066,0.9615927477982519,0.9668692814989756,0.9191053856724077,0.9717827975697478,0.9677049141291735,0.9682013305347521]
gibbon_ub = [0.9733474160530214,0.9731676108002453,0.9797498052964074,0.9354812685668229,0.9837185468991106,0.9779881019230726,0.9742702266585801] 


#marmoset greedy 
tot_compile_greedy = [0.9543266296386719,0.952153205871582,0.9502048492431641,0.9125690460205078,0.9581794738769531,0.9601764678955078,0.9542787075042725]
greedy_lb = [0.9395896722315223,0.944400543160545,0.9427559402864358,0.9080648920030837,0.9566546337910777,0.9530116236533243,0.9307631870241089] 
greedy_ub = [0.9585955809117882,0.9580711581435729,0.9562467177098477,0.9168423048895488,0.9591993434122914,0.964566225840762,0.9602882113591376]

delta_error_gibbon = [element1 - element2 for (element1, element2) in zip(gibbon_ub, gibbon_lb)]

delta_error_greedy = [element1 - element2 for (element1, element2) in zip(greedy_ub, greedy_lb)]

plt.ylim([0, 16])

# Stacked bar chart, gibbon
ax.bar(values, tot_compile_gibbon, yerr = delta_error_gibbon , width=width, ecolor = 'black', color= 'green', error_kw=dict(lw=1, capsize=2, capthick=1))

#Stacked bar chart greedy 
ax.bar(values + width, tot_compile_greedy, yerr = delta_error_greedy , width=width, ecolor = 'black', color= 'yellow', error_kw=dict(lw=1, capsize=2, capthick=1))

# Stacked bar chart, marmoset
ax.bar(values + width*2 , t_compile, yerr = delta_error_solver , width=width, ecolor = 'black', color= 'blue')
ax.bar(values + width*2, solver, yerr = delta_error_compile , width=width, ecolor = 'black', bottom = t_compile, color= 'red', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Time in Seconds", fontsize ='36')

plt.yticks(fontsize='32')

Legend = ['gibbon', 'marmoset greedy', 'marmoset - (solver + IO) ', 'solver + IO']

ax.legend(Legend, loc = 2, fontsize=32)


fig.set_size_inches(16, 8)                                                                                                                                    
plt.savefig('TagSearchCompileTimes.pdf', dpi=4000, format='pdf', bbox_inches='tight')
#plt.show() 

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


#GHC VS GIBBON SPEEDUPS Filter Blogs
width = 0.4
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

Marmoset_Median = 0.065
Marmoset_UB     = 0.06500446729509662
Marmoset_LB     = 0.06578108826045892

Ghc = [(0.225395476/Marmoset_Median),(0.225769255/Marmoset_Median),(0.214234569/Marmoset_Median), (0.223801856/Marmoset_Median), (0.211657778/Marmoset_Median), (0.218405599/Marmoset_Median), (0.230497711/Marmoset_Median)] 
ErrorBarGhcLb = [(0.22429329448170157/Marmoset_UB),(0.22459338544449045/Marmoset_UB),(0.212920461807541/Marmoset_UB), (0.22280862150748224/Marmoset_UB), (0.2101991556628915/Marmoset_UB), (0.21738497102868323/Marmoset_UB), (0.22989495707724106/Marmoset_UB)]
ErrorBarGhcUb = [(0.22756159240718735/Marmoset_LB),(0.2267582294443984/Marmoset_LB),(0.21495953797023679/Marmoset_LB), (0.2253176862702956/Marmoset_LB), (0.21630266855933072/Marmoset_LB), (0.219801701193539/Marmoset_LB), (0.2316596989227589/Marmoset_LB)] 

delta_error_ghc = [abs(element1 - element2) for (element1, element2) in zip(ErrorBarGhcUb, ErrorBarGhcLb)]
plt.ylim([0, 6])

# Stacked bar chart, marmoset
ax.bar(values , Ghc, yerr = delta_error_ghc , width=width, ecolor = 'black', color= 'blue', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Speedup", fontsize ='36')

plt.yticks(fontsize='32')

plt.axhline(y=1, color='r', linestyle='--', lw=2)

fig.set_size_inches(16, 5)                                                                                                                                    
plt.savefig('SpeedupMarmosetGhcFilterBlogs.pdf', dpi=4000, format='pdf', bbox_inches='tight')
 
#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


#GHC VS GIBBON SPEEDUPS Content Search
width = 0.4
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

Marmoset_Median = 0.637
Marmoset_UB     = 0.6352029703132667
Marmoset_LB     = 0.639036807464511

Ghc = [(3.626187277/Marmoset_Median),(3.57383524/Marmoset_Median),(3.684741551/Marmoset_Median), (3.632958663/Marmoset_Median), (3.638080366/Marmoset_Median), (3.585630508/Marmoset_Median), (3.599035579/Marmoset_Median)] 

ErrorBarGhcLb = [(3.584182679694473/Marmoset_UB),(3.497106889117984/Marmoset_UB),(3.5843370635607665/Marmoset_UB), (3.5480737523985537/Marmoset_UB), (3.5766176723174516/Marmoset_UB), (3.5249513016925893/Marmoset_UB), (3.53552073656425/Marmoset_UB)]

ErrorBarGhcUb = [(3.700556361416638/Marmoset_LB),(3.6252115513264593/Marmoset_LB),(3.7325632782170115/Marmoset_LB), (3.700484465823669/Marmoset_LB), (3.6950645536825486/Marmoset_LB), (3.6559300227518547/Marmoset_LB), (3.655430860991307/Marmoset_LB)] 

delta_error_ghc = [element1 - element2 for (element1, element2) in zip(ErrorBarGhcUb, ErrorBarGhcLb)]
plt.ylim([0, 8])

# Stacked bar chart, marmoset
ax.bar(values , Ghc, yerr = delta_error_ghc , width=width, ecolor = 'black', color= 'blue', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Speedup", fontsize ='36')

plt.yticks(fontsize='32')

plt.axhline(y=1, color='r', linestyle='--', lw=2)

fig.set_size_inches(16, 5)                                                                                                                                    
plt.savefig('SpeedupMarmosetGhcContentSearch.pdf', dpi=4000, format='pdf', bbox_inches='tight')

 

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#GHC VS GIBBON SPEEDUPS Tag Search
width = 0.4
groups = ['hiadctb', 'ctbhiad', 'tbchiad', 'tcbhiad', 'btchiad', 'bchiadt', 'cbiadht']
values = np.arange(len(groups))

fig, ax = plt.subplots()

#Marmoset

Marmoset_Median = 2.216
Marmoset_UB     = 2.21056925710439
Marmoset_LB     = 2.2326018540067203

Ghc = [(12.196863463/Marmoset_Median),(12.110002843/Marmoset_Median),(14.40740848/Marmoset_Median), (12.310711557/Marmoset_Median), (14.252560143/Marmoset_Median), (14.252560143/Marmoset_Median), (14.252560143/Marmoset_Median)] 

ErrorBarGhcLb = [(11.808613241352441/Marmoset_UB),(11.759131672706282/Marmoset_UB),(14.308582698203264/Marmoset_UB), (12.227651187984256/Marmoset_UB), (14.111179461701267/Marmoset_UB), (14.158143463814984/Marmoset_UB), (12.229775082548432/Marmoset_UB)]

ErrorBarGhcUb = [(13.083980757758669/Marmoset_LB),(13.477219183293716/Marmoset_LB),(14.56685479979674/Marmoset_LB), (12.385758416904634/Marmoset_LB), (14.407891856076512/Marmoset_LB), (14.361631075073905/Marmoset_LB), (12.589485113007125/Marmoset_LB)] 

delta_error_ghc = [element1 - element2 for (element1, element2) in zip(ErrorBarGhcUb, ErrorBarGhcLb)]
plt.ylim([0, 8])

# Stacked bar chart, marmoset
ax.bar(values , Ghc, yerr = delta_error_ghc , width=width, ecolor = 'black', color= 'blue', error_kw=dict(lw=1, capsize=2, capthick=1))

plt.xticks(values, groups, color='black', rotation=25, fontweight='normal', fontstyle='italic', fontsize='36', horizontalalignment='center')

plt.xlabel("Layout Name", fontsize='36')
plt.ylabel("Speedup", fontsize ='36')

plt.yticks(fontsize='32')

plt.axhline(y=1, color='r', linestyle='--', lw=2)

fig.set_size_inches(16, 5)                                                                                                                                    
plt.savefig('SpeedupMarmosetGhcTagSearch.pdf', dpi=4000, format='pdf', bbox_inches='tight')
plt.show() 
