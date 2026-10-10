from z3 import * 

#Constraints for tag search example

#Fields that are being used, based on the graph
tags, content, blogList = Ints('tags content blogList')

#costs across each edge in the graph
c1 , c2, c3 = Ints('c1 c2 c3')

s = Optimize() 

# Costs c1, c2 and c3 are costs to backtrack, pointer deference or more than one of either. 

# Constraints for edge tags -> blogList
s.add(Implies(tags - blogList == -1, c1 == 0))  # <- If fields are adjacent then no cost to traverse from tags to blogList
s.add(Implies(tags - blogList  < -1, c1 == 100)) # <- If there are more than 1 fields in between then we pay a constant cost to go from tags to blogList (pointer dereference)
s.add(Implies(tags - blogList ==  1, c1 == 200)) # <- If tags is after blogList, we do a pointer dereference + backtrack to go back to blogList
s.add(Implies(tags - blogList   > 1, c1 == 200))  # <- If tags is after blogList + there are more than 1 fields in between then we again do a pointer dereference + backtrack 
                                                # However, since there are more fields this should be higher for now assume same as prior case.


# Constraints for edge tags -> content 
s.add(Implies(tags - content == -1, c2 == 0))   #No cost
s.add(Implies(tags - content  < -1, c2 == 100)) #Pointer dereference cost to jump to the content field
s.add(Implies(tags - content  == 1, c2 == 200)) #Pointer dereference cost to jump to tags then backtrack to get to beginning of tags
s.add(Implies(tags - content   > 1, c2 == 200))   #Pointer dereference cost to jump to tags then backtrack to get to beginning of tags (This should be higher)

# Constraints for edge content -> blogList 
s.add(Implies(content - blogList == -1, c3 == 0))   #No cost
s.add(Implies(content - blogList  < -1, c3 == 100)) #Pointer dereference cost to jump to blogList
s.add(Implies(content - blogList  == 1, c3 == 200)) #Pointer dereference cost to jump to content then backtrack to get to beginning of content
s.add(Implies(content - blogList   > 1, c3 == 200)) #Pointer dereference cost to jump to blogList then backtrack to get to beginning of content (This should be higher but for now assume same as prior step)


#define the domain, the compiler should spit these constraints out
#Since the number of fields in use are 3, we define domain from 0 to (3 - 1)

# 0 <= 
s.add(0 <= tags)
s.add(0 <= content)
s.add(0 <= blogList)

# <= 2 
s.add(tags <= 2)
s.add(content <= 2)
s.add(blogList <= 2)

#Constraint that all indexes should be unique. 
s.add(tags != content)
s.add(tags != blogList)
s.add(content != blogList)

#Constraint all costs are greater than equal to 0 
s.add(c1 >= 0)
s.add(c2 >= 0)
s.add(c3 >= 0)

#Minimize the costs along all the edges, multiply by likelihood percentage along that edge.
s.minimize((c1*50) + (c2*50) + (c3*50))


print(s.check())
print(s.model())