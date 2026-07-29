import { create } from "zustand";

/** Tiny bus so Fleet (and others) can open the Activity rail dialog. */
type ActivityUiState = {
  open: boolean;
  setOpen: (open: boolean) => void;
  requestOpen: () => void;
};

export const useActivityUiStore = create<ActivityUiState>((set) => ({
  open: false,
  setOpen: (open) => set({ open }),
  requestOpen: () => set({ open: true }),
}));
