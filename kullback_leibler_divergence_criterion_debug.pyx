
# Author: Laurenz Ruzicka
# Base on the work from Evgeni Dubov <evgeni.dubov@gmail.com>
#
# License: MIT
#sklearn imports
from sklearn.tree._criterion cimport ClassificationCriterion
from sklearn.tree._criterion cimport SIZE_t
from sklearn.tree._utils cimport log

#default imports
import numpy as np
cdef double INFINITY = np.inf

#math imports
from libc.math cimport sqrt, pow
from libc.math cimport abs

cdef bint DEBUG = False
cdef bint DEBUG_proxy = False
choice = 'kule'

cdef class KullbackLeibnerCriterion(ClassificationCriterion):
    cdef double proxy_impurity_improvement(self) nogil:
        '''Compute a proxy of the impurity reduction
        This method is used to speed up the search for the best split.
        It is a proxy quantity such that the split that maximizes this value
        also maximizes the impurity improvement. It neglects all constant terms
        of the impurity decrease for a given split.
        The absolute impurity improvement is only computed by the
        impurity_improvement method once the best split has been found.'''
        
        cdef double impurity_left
        cdef double impurity_right
        self.children_impurity(&impurity_left, &impurity_right)
        if DEBUG_proxy: 
            with gil:
                print "proxy_impurity_improvement " + str((- self.weighted_n_right * impurity_right
                - self.weighted_n_left * impurity_left))
 
        return (- self.weighted_n_right * impurity_right
                - self.weighted_n_left * impurity_left)

    cdef double impurity_improvement(self, double impurity) nogil:
        '''Compute the improvement in impurity
        This method computes the improvement in impurity when a split occurs.
        The weighted impurity improvement equation is the following:
            N_t / N * (impurity - N_t_R / N_t * right_impurity
                                - N_t_L / N_t * left_impurity)
        where N is the total number of samples, N_t is the number of samples
        at the current node, N_t_L is the number of samples in the left child,
        and N_t_R is the number of samples in the right child,
        Parameters
        ----------
        impurity : double
            The initial impurity of the node before the split
        Return
        ------
        double : improvement in impurity after the split occurs'''
        

        cdef double impurity_left
        cdef double impurity_right

        self.children_impurity(&impurity_left, &impurity_right)
        if DEBUG:
            with gil:
                print "Impurity Improvement " + str(((self.weighted_n_node_samples / self.weighted_n_samples) *
                (impurity - (self.weighted_n_right /
                             self.weighted_n_node_samples * impurity_right)
                          - (self.weighted_n_left /
                             self.weighted_n_node_samples * impurity_left))))

        return ((self.weighted_n_node_samples / self.weighted_n_samples) *
                (impurity - (self.weighted_n_right / 
                             self.weighted_n_node_samples * impurity_right)
                          - (self.weighted_n_left / 
                             self.weighted_n_node_samples * impurity_left)))


    cdef double node_impurity(self) nogil:
        
        cdef SIZE_t* n_classes = self.n_classes
        cdef double* sum_total = self.sum_total
        cdef double kule    = 0.0
        cdef double entropy = 0.0
        cdef double gini    = 0.0
        cdef double hellinger = 0.0
        cdef double rho
        cdef double rho_0
        cdef double sq_count
        cdef double count_k
        cdef SIZE_t k
        cdef SIZE_t c

        with gil:
          assert self.n_outputs == 1,    "Only one output with Kullback-Leibner Criterion"
          assert self.n_classes[0] == 2, "Only two classes with Kullback-Leibner Criterion"
        
        for k in range(self.n_outputs):
            # Gini
            if DEBUG:
                sq_count = 0.0

                for c in range(n_classes[k]):
                    count_k = sum_total[c]
                    sq_count += count_k * count_k

                gini += 1.0 - sq_count / (self.weighted_n_node_samples *
                                      self.weighted_n_node_samples)

                # Entropy
                for c in range(n_classes[k]):
                    count_k = sum_total[c]
                    if count_k > 0.0:
                        count_k /= self.weighted_n_node_samples
                        entropy -= count_k * log(count_k)

            # kule
            rho   = sum_total[1]/self.weighted_n_node_samples
            if DEBUG: rho_0 = sum_total[0]/self.weighted_n_node_samples # for debugging
            if rho==1:
                kule  = -INFINITY
                #kule = 0 fake gini
            #elif rho == 0.5:
            #
            #    kule = 0
            elif rho>0:
                #kule  = -rho*log(rho/(1-rho))
                kule  = 0.5*rho - 0.25*rho*log(rho/(1-rho))
                #kule = 1.0 - (rho_0**2 + rho**2)
            else:
                kule = 0

            # Hellinger
            if DEBUG:
                for c in range(n_classes[k]):
                    hellinger += 1.0

            # This sum is gloablly relevant! It moves the array Pointer to the next entry
            sum_total += self.sum_stride


        with gil:
            if DEBUG:
                print "node_impurity: gini %6.4f entropy %6.4f kule %6.4f hellinger %6.4f" %( gini, entropy, kule, hellinger )
                print "  sum_total[0] %6.4f sum_total[1] %6.4f" %( sum_total[0], sum_total[1] )
                print "  weighted_n_node_samples %6.4f" %( self.weighted_n_node_samples )
                print "  rho %6.4f rho_0 %6.4f" %( rho, rho_0 )
            
            if choice == 'gini':
                return gini / self.n_outputs
            elif choice == 'kule':
                return kule / self.n_outputs
            elif choice == 'entropy':
                return entropy / self.n_outputs
            elif choice == 'hellinger':
                return hellinger / self.n_outputs


    cdef void children_impurity(self, double* impurity_left,
                                double* impurity_right) nogil:

        cdef SIZE_t* n_classes = self.n_classes
        cdef double* sum_left = self.sum_left
        cdef double* sum_right = self.sum_right
        cdef double kule_left = 0.0
        cdef double kule_right = 0.0
        cdef double kule = 0.0
        cdef double rho = 0.0
        cdef double gini_left = 0.0
        cdef double gini_right = 0.0
        cdef double entropy_left = 0.0
        cdef double entropy_right = 0.0
        cdef double hellinger_left = 0.0
        cdef double hellinger_right = 0.0
        cdef double sq_count_left
        cdef double sq_count_right
        cdef double rho_left
        cdef double rho_right
        cdef double count_k
        cdef SIZE_t k
        cdef SIZE_t c

        with gil:
          assert self.n_outputs == 1,    "Only one output with Kullback-Leibner Criterion"
          assert self.n_classes[0] == 2, "Only two classes with Kullback-Leibner Criterion"


        for k in range(self.n_outputs):
            # Gini
            if DEBUG:
                sq_count_left = 0.0
                sq_count_right = 0.0

                for c in range(n_classes[k]):
                    count_k = sum_left[c]
                    sq_count_left += count_k * count_k

                    count_k = sum_right[c]
                    sq_count_right += count_k * count_k

                gini_left += 1.0 - sq_count_left / (self.weighted_n_left *
                                                self.weighted_n_left)

                gini_right += 1.0 - sq_count_right / (self.weighted_n_right *
                                                  self.weighted_n_right)

                # Entropy
                for c in range(n_classes[k]):
                    count_k = sum_left[c]
                    if count_k > 0.0:
                        count_k /= self.weighted_n_left
                        entropy_left -= count_k * log(count_k)

                    count_k = sum_right[c]
                    if count_k > 0.0:
                        count_k /= self.weighted_n_right
                        entropy_right -= count_k * log(count_k)

            # kule
            rho_left = sum_left[1]/self.weighted_n_left
            if DEBUG: rho_0_left = sum_left[0]/self.weighted_n_left # for debugging
            if rho_left == 1:
                kule_left = -INFINITY
                #kule_left = 0.
            #elif rho_left == 0.5:
            #    kule_left = 0
            elif rho_left > 0:
                #kule_left = -rho_left*log(rho_left/(1-rho_left))
                kule_left = 0.5*rho_left - 0.25*rho_left*log(rho_left/(1-rho_left))
                #kule_left = 1.0-(rho_0_left**2 + rho_left**2)
            else:
                kule_left = 0.

            rho_right  = sum_right[1]/self.weighted_n_right
            if DEBUG: rho_0_right = sum_right[0]/self.weighted_n_right # for debugging
            if rho_right == 1:
                kule_right = -INFINITY
                #kule_right = 0.
            #elif rho_right == 0.5:
            #    kule_right = 0
            elif rho_right > 0:
                #kule_right = -rho_right*log(rho_right/(1-rho_right))
                kule_right = 0.5*rho_right - 0.25*rho_right*log(rho_right/(1-rho_right))
                #kule_right = 1.0 - (rho_0_right**2 + rho_right**2) 
            else:
                kule_right = 0.
            
            if DEBUG:
                # for debugging: compute the mother impurity
                rho  = (sum_left[1] + sum_right[1])/(self.weighted_n_left + self.weighted_n_right)
                if rho == 1:
                    kule = - INFINITY
                elif rho > 0:
                    kule = 0.5*rho - 0.25*rho*log(rho/(1-rho))
                else:
                    kule = 0.

                # Hellinger
                # stop splitting in case reached pure node with 0 samples of second class
                if sum_left[1] + sum_right[1] == 0:
                    impurity_left[0] = -INFINITY
                    impurity_right[0] = -INFINITY
                else:

                    if(sum_left[0] + sum_right[0] > 0):
                        count_k1 = sqrt(sum_left[0] / (sum_left[0] + sum_right[0]))
                    if(sum_left[1] + sum_right[1] > 0):
                        count_k2 = sqrt(sum_left[1] / (sum_left[1] + sum_right[1]))

                    hellinger_left += pow((count_k1  - count_k2),2)

                    if(sum_left[0] + sum_right[0] > 0):
                        count_k1 = sqrt(sum_right[0] / (sum_left[0] + sum_right[0]))
                    if(sum_left[1] + sum_right[1] > 0):
                        count_k2 = sqrt(sum_right[1] / (sum_left[1] + sum_right[1]))

                    hellinger_right += pow((count_k1  - count_k2),2)

            # Careful! This is a global sum! Can only do once and only at the end of this loop.
            sum_left += self.sum_stride
            sum_right += self.sum_stride

        with gil:
            #DeltaKule =  - self.weighted_n_left*kule_left - self.weighted_n_right*kule_right + (self.weighted_n_left+self.weighted_n_right)*kule
            #print "children_impurity: kule_left %6.4f kule_right %6.4f kule_tot %6.4f DeltaKule %6.4f"%( kule_left, kule_right, kule, DeltaKule)
            if choice == 'gini':
                impurity_left[0] = gini_left / self.n_outputs
                impurity_right[0] = gini_right / self.n_outputs
            elif choice == 'entropy':
                impurity_left[0] = entropy_left / self.n_outputs
                impurity_right[0] = entropy_right / self.n_outputs
            elif choice == 'kule':
                impurity_left[0]  = kule_left / self.n_outputs
                impurity_right[0] = kule_right / self.n_outputs
            elif choice == 'hellinger':
                impurity_left[0]  = hellinger_left  / self.n_outputs
                impurity_right[0] = hellinger_right / self.n_outputs