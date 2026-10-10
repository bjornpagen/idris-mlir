# load data
#p7ih_dist<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/p7ih_dist_256.data")
#p7ih_glb<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/p7ih_glb_256.data")

p7ih_dist<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/p7ih_dist_256_n17.data")
p7ih_glb<-scan("~/hpcc13/assembla/trunk/ppopp14_workshop/data/bc/p7ih_glb_256_n17.data")


pdf("../p7ih_workload.pdf");
par(mfrow=c(1,2));
# draw dist workload
mean_dist=mean(p7ih_dist);
sd_dist=sd(p7ih_dist);
xlab_txt=sprintf("Places(0..255), mean:%.3f, sd:%.3f", mean_dist, sd_dist);
barplot(p7ih_dist, main="BC", xlab=xlab_txt, ylab="Execution time per place", xlim=c(0,255), ylim=c(0,30));
# draw glb workload
mean_glb=mean(p7ih_glb)
sd_glb=sd(p7ih_glb)
xlab_txt=sprintf("Places(0..255), mean:%.3f, sd:%.3f", mean_glb, sd_glb);
barplot(p7ih_glb, main="BC-G", xlab=xlab_txt, ylab="Execution time per place", xlim=c(0,255), ylim=c(0,30));
dev.off()

 
