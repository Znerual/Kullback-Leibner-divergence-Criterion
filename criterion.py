#default imports
import ROOT
import numpy as np

class KullbackLeibler:
    def __init__(self, logger):
        self.logger = logger
    
    def kule_div(self, sm, bsm, start_index_offset = 0):
        #checking for correct input
        assert sm.GetNbinsX() == bsm.GetNbinsX(), "Different Bin counts, in criterion.py"
        assert start_index_offset < sm.GetNbinsX(), "The offsetvalue is too big"
          
        kule = 0
        varianz = 0
        
        #loop over all the selected histo bins
        for i in range(1 + start_index_offset,bsm.GetNbinsX()+1):
            p = bsm.GetBinContent(i)
            q = sm.GetBinContent(i)
            w_bsm = bsm.GetBinError(i)
            w_sm = sm.GetBinError(i)
            
            #round, to avoid 0 != 0 
            if round(p,6) ==  0.0 and round(q,6) == 0.0: continue
            with np.errstate(divide='raise'): #this makes numpy warnings to Exceptions which can be caught
                try:
                    lg = np.log(p/q)
                    kule += p * lg - (p - q)
                    varianz += np.square(w_bsm) * (np.square(1.0 + lg)) + np.square(p * w_sm/ q) #nicht error nennen, varianz
                except ZeroDivisionError:                    
                    self.logger.warning("Kule Divided by zero np.log(%f/%f), at bin %i with bin SM Error %f and BSM error %f", p,q, i, w_sm, w_bsm) 
                except FloatingPointError:
                    self.logger.warning("Kule Floating Point Error np.log(%f/%f) at bin %i with error bins SM: %f and BSM: %f", p,q, i, w_sm, w_bsm) 
                     
        return kule, np.sqrt(varianz)#return std (wurzel)
class Gini:
    def __init__(self, logger):
        self.logger = logger
    def gini(self, sm, bsm, start_index_offset=0):
        #checking for correct input
        assert sm.GetNbinsX() == bsm.GetNbinsX(), "Different Bin counts, in criterion.py"
        assert sm.GetNbinsX() == bsm.GetNbinsX(), "Different Bin counts, in criterion.py"
        assert start_index_offset < sm.GetNbinsX()
        gini = 0
        varianz = 0
        
        #looping over the selected bins
        for i in range(1 + start_index_offset,bsm.GetNbinsX()+1):
            #reading out the bins
            p = bsm.GetBinContent(i)
            q = sm.GetBinContent(i)
            w_bsm = bsm.GetBinError(i)
            w_sm = sm.GetBinError(i)

            #round to skip when both bins are empty
            if  (round(p,6) ==  0.0 and round(q,6) == 0.0): continue
            with np.errstate(divide='raise'): #to catch numpy warnings
                try:
                    gini += (p / np.sqrt(p + q))
                    varianz_nenner = 4.0 * (p + q)**3
                    varianz += ((p + 2.0*q) * w_bsm) **2 / varianz_nenner  + (p * w_sm)**2 / varianz_nenner
                except FloatingPointError:
                    self.logger.warning("Gini Floating Point Error BSM bin: %f, SM bin: %f,  at bin %i with error bins SM: %f and BSM: %f", p,q, i, w_sm, w_bsm) 
        
        return gini, np.sqrt(varianz)
